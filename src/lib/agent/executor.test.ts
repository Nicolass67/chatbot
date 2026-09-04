import { describe, expect, it, vi } from "vitest";
import { executeToolCalls } from "./executor";
import { analyzeTemporalContext } from "./temporal";
import type { AgentPlan } from "./types";
import type { AppSettings } from "@/lib/settings/service";

const SEPT_2026_CLOCK = {
  currentDate: "2026-09-01",
  currentDateTime: "01/09/2026 12:00:00",
  timezone: "Europe/Paris",
  currentYear: 2026,
  currentMonth: 9,
};

const temporalContext = analyzeTemporalContext(
  "test recherche",
  SEPT_2026_CLOCK
);

vi.mock("@/lib/tools/execute-with-policy", () => ({
  executeToolWithPolicy: vi.fn(async (name: string, input: { query?: string }) => ({
    query: input.query ?? "test",
    results: [{ title: "R", url: "https://x.com", domain: "x.com", snippet: "s" }],
  })),
}));

vi.mock("@/lib/db", () => ({
  getDb: () => ({
    insert: () => ({ values: async () => {} }),
  }),
}));

const baseSettings = {
  selectedModel: "test",
  temperature: 0.7,
  maxTokens: 4096,
  contextLength: 8192,
  systemPrompt: "",
  memoryEnabled: true,
  webSearchEnabled: true,
  webSearchMaxResults: 5,
  webSearchTimeoutMs: 10000,
  idleTimeoutMinutes: 10,
  recentMessagesCount: 10,
  maxAttachmentSizeMb: 20,
  maxAttachmentsPerMessage: 10,
  defaultReasoningEffort: "off",
  agentMaxStepsFast: 5,
  agentMaxStepsStandard: 12,
  agentMaxStepsThorough: 25,
  agentMaxToolCalls: 40,
  agentMaxExecutionTimeMs: 300000,
} satisfies AppSettings;

const plan: AgentPlan = {
  steps: [
    { id: "step-1", title: "Recherche", status: "active", actions: [] },
  ],
};

describe("executeToolCalls", () => {
  it("executes multiple calls in parallel by default", async () => {
    const starts: string[] = [];
    await executeToolCalls({
      calls: [
        { tool: "web_search", input: { query: "a" } },
        { tool: "web_search", input: { query: "b" } },
      ],
      plan,
      conversationId: "conv-1",
      settings: baseSettings,
      userGoal: "test recherche",
      temporalContext,
      callbacks: {
        onActionStart: () => {},
        onActionDone: () => {},
        onToolStart: (_, input) => starts.push((input as { query: string }).query),
        onToolDone: () => {},
        onSources: () => {},
      },
    });
    expect(starts).toHaveLength(2);
    expect(starts).toContain("a");
    expect(starts).toContain("b");
  });

  it("executes calls sequentially when parallel is false", async () => {
    const order: string[] = [];
    await executeToolCalls({
      calls: [
        { tool: "web_search", input: { query: "a" } },
        { tool: "web_search", input: { query: "b" } },
      ],
      parallel: false,
      plan,
      conversationId: "conv-1",
      settings: baseSettings,
      userGoal: "test recherche",
      temporalContext,
      callbacks: {
        onActionStart: () => {},
        onActionDone: () => {},
        onToolStart: (_, input) => order.push((input as { query: string }).query),
        onToolDone: () => {},
        onSources: () => {},
      },
    });
    expect(order).toEqual(["a", "b"]);
  });

  it("executes calls in parallel when explicitly requested", async () => {
    const starts: string[] = [];
    await executeToolCalls({
      calls: [
        { tool: "web_search", input: { query: "x" } },
        { tool: "web_search", input: { query: "y" } },
      ],
      parallel: true,
      plan,
      conversationId: "conv-1",
      settings: baseSettings,
      userGoal: "test recherche",
      temporalContext,
      callbacks: {
        onActionStart: () => {},
        onActionDone: () => {},
        onToolStart: (_, input) => starts.push((input as { query: string }).query),
        onToolDone: () => {},
        onSources: () => {},
      },
    });
    expect(starts).toHaveLength(2);
    expect(starts).toContain("x");
    expect(starts).toContain("y");
  });

  it("throws on abort signal", async () => {
    const controller = new AbortController();
    controller.abort();
    await expect(
      executeToolCalls({
        calls: [{ tool: "web_search", input: { query: "z" } }],
        plan,
        conversationId: "conv-1",
        settings: baseSettings,
        signal: controller.signal,
        userGoal: "test recherche",
        temporalContext,
        callbacks: {
          onActionStart: () => {},
          onActionDone: () => {},
          onToolStart: () => {},
          onToolDone: () => {},
          onSources: () => {},
        },
      })
    ).rejects.toThrow();
  });

  it("corrige une requête web avec année historique non demandée", async () => {
    const gpuTemporal = analyzeTemporalContext(
      "meilleurs GPU sous 1000 € actuellement",
      SEPT_2026_CLOCK
    );
    const started: Array<{ query: string }> = [];
    await executeToolCalls({
      calls: [
        {
          tool: "web_search",
          input: { query: "meilleurs GPU sous 1000 € 2024" },
        },
      ],
      plan,
      conversationId: "conv-1",
      settings: baseSettings,
      userGoal: "meilleurs GPU sous 1000 € actuellement",
      temporalContext: gpuTemporal,
      callbacks: {
        onActionStart: () => {},
        onActionDone: () => {},
        onToolStart: (_, input) => started.push(input as { query: string }),
        onToolDone: () => {},
        onSources: () => {},
      },
    });
    expect(started[0]?.query).toBeDefined();
    expect(started[0]!.query).not.toMatch(/\b2024\b/);
  });
});
