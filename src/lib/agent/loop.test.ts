import { describe, expect, it, vi, beforeEach } from "vitest";
import { runAgentLoop } from "./loop";
import type { OrchestratorEvent } from "./events";
import type { RouteDecision } from "@/lib/request-router/types";
import { EMPTY_EMAIL_ROUTE, EMPTY_FILES_ROUTE } from "@/lib/request-router/email-intent";

function buildTestRoute(
  userContent: string,
  overrides: Partial<RouteDecision> = {}
): RouteDecision {
  return {
    knowledge: "static",
    web: {
      enabled: true,
      mode: "none",
      searchType: "none",
      wouldBeUseful: false,
      mandatory: false,
      autoSearch: false,
      searchQuery: userContent,
      reason: "test",
    },
    email: EMPTY_EMAIL_ROUTE,
    files: EMPTY_FILES_ROUTE,
    research: {},
    execution: { mode: "agent", suggestAgent: false },
    vision: { required: false, reason: "" },
    tools: { allowToolCalling: false, candidates: [] },
    temporal: {
      clock: {
        currentDate: "2026-09-01",
        currentDateTime: "01/09/2026",
        timezone: "Europe/Paris",
        currentYear: 2026,
        currentMonth: 9,
      },
      scope: "unspecified",
      referenceYear: null,
      userIntent: "test",
      isTimeSensitive: false,
      userMentionedYears: [],
    },
    confidence: 0.9,
    source: "fallback_conservative",
    reason: "test",
    latencyMs: 0,
    ...overrides,
  };
}

function buildFreshWebRoute(userContent: string): RouteDecision {
  return buildTestRoute(userContent, {
    knowledge: "current",
    web: {
      enabled: true,
      mode: "required",
      searchType: "single",
      wouldBeUseful: true,
      mandatory: true,
      autoSearch: false,
      searchQuery: userContent,
      reason: "test",
    },
    tools: { allowToolCalling: true, candidates: ["web_search"] },
    temporal: {
      clock: {
        currentDate: "2026-09-01",
        currentDateTime: "01/09/2026",
        timezone: "Europe/Paris",
        currentYear: 2026,
        currentMonth: 9,
      },
      scope: "current",
      referenceYear: null,
      userIntent: "Informations actuelles",
      isTimeSensitive: true,
      userMentionedYears: [],
    },
  });
}

const mockChat = vi.fn();
const mockStream = vi.fn();
const mockAbort = vi.fn();

vi.mock("@/lib/tools/registry", () => ({
  getRegisteredTools: () => [{ name: "web_search" }],
  executeTool: vi.fn(async (_name: string, input: { query: string }) => ({
    query: input.query,
    results: [],
  })),
}));

vi.mock("@/lib/db", () => ({
  getDb: () => ({
    insert: () => ({ values: async () => {} }),
    update: () => ({ set: () => ({ where: async () => {} }) }),
    query: {
      conversations: { findFirst: async () => ({ title: "Test" }) },
      agentRuns: { findFirst: async () => null },
      messages: { findMany: async () => [] },
    },
  }),
}));

vi.mock("@/lib/memory/heuristics", () => ({ shouldExtractMemory: () => false }));
vi.mock("@/lib/memory/extract", () => ({ extractMemoriesAsync: vi.fn() }));
vi.mock("@/lib/conversation/title-generator", () => ({
  maybeGenerateConversationTitle: vi.fn(),
}));
vi.mock("@/lib/context/summarizer", () => ({
  maybeSummarizeConversation: vi.fn(),
}));

vi.mock("@/lib/tools/web-search/web-search-availability", () => ({
  evaluateWebSearchAvailability: vi.fn(),
}));

vi.mock("./executor", () => ({
  executeToolCalls: vi.fn(),
}));

import { evaluateWebSearchAvailability } from "@/lib/tools/web-search/web-search-availability";
import { executeToolCalls } from "./executor";

const baseSettings = {
  selectedModel: "test-model",
  temperature: 0.7,
  maxTokens: 4096,
  contextLength: 8192,
  systemPrompt: "Test",
  memoryEnabled: false,
  webSearchEnabled: true,
  webSearchMaxResults: 5,
  webSearchTimeoutMs: 10000,
  idleTimeoutMinutes: 10,
  recentMessagesCount: 10,
  maxAttachmentSizeMb: 20,
  maxAttachmentsPerMessage: 10,
  defaultReasoningEffort: "off",
  agentMaxStepsFast: 2,
  agentMaxStepsStandard: 12,
  agentMaxStepsThorough: 25,
  agentMaxToolCalls: 5,
  agentMaxExecutionTimeMs: 300000,
};

describe("runAgentLoop", () => {
  beforeEach(() => {
    mockChat.mockReset();
    mockStream.mockReset();
    mockAbort.mockReset();
    vi.mocked(executeToolCalls).mockClear();
    vi.mocked(evaluateWebSearchAvailability).mockClear();
    vi.mocked(evaluateWebSearchAvailability).mockResolvedValue({
      available: true,
      provider: "searxng",
      searxng: {
        status: "connected",
        url: "http://localhost:8080",
        checkedAt: new Date().toISOString(),
      },
    });
    vi.mocked(executeToolCalls).mockResolvedValue([]);
  });

  it("stops when maxSteps is reached", async () => {
    mockChat
      .mockResolvedValueOnce({
        content: JSON.stringify({
          steps: [
            { id: "step-1", title: "A" },
            { id: "step-2", title: "B" },
          ],
        }),
      })
      .mockResolvedValue({
        content: JSON.stringify({
          type: "tool_calls",
          calls: [{ tool: "web_search", input: { query: "test" } }],
        }),
        usage: { promptTokens: 10, completionTokens: 5 },
      });

    mockStream.mockImplementation(async (_req, callbacks) => {
      callbacks.onToken("RÃ©ponse finale.");
      callbacks.onDone({ content: "RÃ©ponse finale." });
    });

    const events: OrchestratorEvent[] = [];
    const controller = new AbortController();

    await runAgentLoop({
      conversationId: "conv-1",
      userContent: "Test question",
      settings: baseSettings,
      runtime: {
        chat: mockChat,
        stream: mockStream,
        abort: mockAbort,
      } as never,
      reasoningEffort: null,
      documentContext: "",
      signal: controller.signal,
      routeDecision: buildTestRoute("Test question"),
      onEvent: (e) => events.push(e),
    });

    expect(events.some((e) => e.type === "agent_plan")).toBe(true);
    expect(events.some((e) => e.type === "agent_limit_reached")).toBe(true);
    expect(events.some((e) => e.type === "done")).toBe(true);
  });

  it("handles abort signal", async () => {
    mockChat.mockResolvedValueOnce({
      content: JSON.stringify({
        steps: [{ id: "step-1", title: "A" }, { id: "step-2", title: "B" }],
      }),
    });

    const controller = new AbortController();
    controller.abort();

    await expect(
      runAgentLoop({
        conversationId: "conv-1",
        userContent: "Test",
        settings: baseSettings,
        runtime: {
          chat: mockChat,
          stream: mockStream,
          abort: mockAbort,
        } as never,
        reasoningEffort: null,
        documentContext: "",
        signal: controller.signal,
        onEvent: () => {},
      })
    ).rejects.toThrow();
  });

  it("Agent nÃ©cessitant le Web â€” SearXNG indisponible, pas de recherche lancÃ©e", async () => {
    vi.mocked(evaluateWebSearchAvailability).mockResolvedValue({
      available: false,
      reason: "SearXNG indisponible â€” impossible de vÃ©rifier les donnÃ©es actuelles.",
      provider: "searxng",
      searxng: {
        status: "unavailable",
        url: "http://localhost:8080",
        checkedAt: new Date().toISOString(),
      },
    });

    mockChat.mockResolvedValueOnce({
      content: JSON.stringify({
        steps: [{ id: "step-1", title: "Recherche GPU" }],
      }),
    });

    mockStream.mockImplementation(async (_req, callbacks) => {
      callbacks.onToken("Impossible de confirmer.");
      callbacks.onDone({ content: "Impossible de confirmer." });
    });

    const events: OrchestratorEvent[] = [];
    const controller = new AbortController();

    await runAgentLoop({
      conversationId: "conv-1",
      userContent:
        "Trouve-moi les trois meilleurs GPU disponibles en France sous 1000 â‚¬ actuellement",
      settings: baseSettings,
      runtime: {
        chat: mockChat,
        stream: mockStream,
        abort: mockAbort,
      } as never,
      reasoningEffort: null,
      documentContext: "",
      signal: controller.signal,
      routeDecision: buildFreshWebRoute(
        "Trouve-moi les trois meilleurs GPU disponibles en France sous 1000 â‚¬ actuellement"
      ),
      onEvent: (e) => events.push(e),
    });

    expect(evaluateWebSearchAvailability).toHaveBeenCalled();
    expect(executeToolCalls).not.toHaveBeenCalled();
    expect(events.some((e) => e.type === "done")).toBe(true);
  });

  it("chat Agent sans Web obligatoire â€” SearXNG indisponible, boucle continue", async () => {
    vi.mocked(evaluateWebSearchAvailability).mockResolvedValue({
      available: false,
      reason: "SearXNG indisponible",
      provider: "searxng",
      searxng: {
        status: "unavailable",
        url: "http://localhost:8080",
        checkedAt: new Date().toISOString(),
      },
    });

    mockChat
      .mockResolvedValueOnce({
        content: JSON.stringify({
          steps: [{ id: "step-1", title: "Expliquer" }],
        }),
      })
      .mockResolvedValue({
        content: JSON.stringify({ type: "finish" }),
        usage: { promptTokens: 10, completionTokens: 5 },
      });

    mockStream.mockImplementation(async (_req, callbacks) => {
      callbacks.onToken("Le ciel est bleu Ã  cause de Rayleigh.");
      callbacks.onDone({ content: "Le ciel est bleu Ã  cause de Rayleigh." });
    });

    const controller = new AbortController();

    await runAgentLoop({
      conversationId: "conv-1",
      userContent: "Pourquoi le ciel est bleu ?",
      settings: baseSettings,
      runtime: {
        chat: mockChat,
        stream: mockStream,
        abort: mockAbort,
      } as never,
      reasoningEffort: null,
      documentContext: "",
      signal: controller.signal,
      routeDecision: buildTestRoute("Pourquoi le ciel est bleu ?"),
      onEvent: () => {},
    });

    expect(evaluateWebSearchAvailability).not.toHaveBeenCalled();
  });
});


