import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/settings/service", () => ({
  getSettings: vi.fn(async () => ({
    memoryEnabled: true,
    selectedModel: "test-model",
  })),
}));

vi.mock("./relevant", () => ({
  loadRelevantMemories: vi.fn(async () => []),
}));

vi.mock("./decision-llm", () => ({
  requestMemoryDecision: vi.fn(),
}));

vi.mock("./apply-decisions", () => ({
  applyValidatedMemoryDecisions: vi.fn(async () => []),
}));

import { getSettings } from "@/lib/settings/service";
import { requestMemoryDecision } from "./decision-llm";
import { applyValidatedMemoryDecisions } from "./apply-decisions";
import {
  runMemoryPostProcessor,
  __resetMemoryPostProcessorLocksForTests,
} from "./run";

describe("runMemoryPostProcessor", () => {
  beforeEach(() => {
    __resetMemoryPostProcessorLocksForTests();
    vi.clearAllMocks();
    vi.mocked(getSettings).mockResolvedValue({
      memoryEnabled: true,
      selectedModel: "test-model",
    } as never);
  });

  it("reste ok si le LLM mémoire est indisponible", async () => {
    vi.mocked(requestMemoryDecision).mockRejectedValue(new Error("llm down"));
    const result = await runMemoryPostProcessor({
      messageId: "m1",
      userMessage: "Je préfère OCCT",
      assistantMessage: "Compris.",
    });
    expect(result.ok).toBe(false);
    expect(result.changed).toBe(false);
    expect(result.error).toMatch(/llm down/);
  });

  it("reste ok si aucune décision (chat toujours OK)", async () => {
    vi.mocked(requestMemoryDecision).mockResolvedValue({ candidates: [] });
    const result = await runMemoryPostProcessor({
      messageId: "m2",
      userMessage: "bonjour",
      assistantMessage: "salut",
    });
    expect(result.ok).toBe(true);
    expect(result.changed).toBe(false);
  });

  it("ignore si mémoire désactivée", async () => {
    vi.mocked(getSettings).mockResolvedValue({
      memoryEnabled: false,
      selectedModel: "test-model",
    } as never);
    const result = await runMemoryPostProcessor({
      userMessage: "Je m'appelle Alice",
      assistantMessage: "Enchanté",
    });
    expect(result.ok).toBe(true);
    expect(requestMemoryDecision).not.toHaveBeenCalled();
  });

  it("empêche deux traitements concurrentes (idempotent lock)", async () => {
    let release!: () => void;
    const gate = new Promise<void>((r) => {
      release = r;
    });
    vi.mocked(requestMemoryDecision).mockImplementation(async () => {
      await gate;
      return { candidates: [] };
    });

    const p1 = runMemoryPostProcessor({
      messageId: "same",
      userMessage: "Je préfère le dark mode",
      assistantMessage: "OK",
    });
    await Promise.resolve();
    const p2 = runMemoryPostProcessor({
      messageId: "same",
      userMessage: "Je préfère le dark mode",
      assistantMessage: "OK",
    });
    const r2 = await p2;
    expect(r2.error).toBe("already_in_flight");
    release();
    const r1 = await p1;
    expect(r1.ok).toBe(true);
  });

  it("applique un CREATE validé", async () => {
    vi.mocked(requestMemoryDecision).mockResolvedValue({
      candidates: [
        {
          action: "create",
          memoryType: "preference",
          content: "L'utilisateur préfère les réponses courtes.",
          existingMemoryId: null,
          confidence: 0.95,
          reason: "pref",
        },
      ],
    });
    vi.mocked(applyValidatedMemoryDecisions).mockResolvedValue([
      {
        action: "create",
        id: "n1",
        content: "L'utilisateur préfère les réponses courtes.",
        category: "preference",
      },
    ]);

    const result = await runMemoryPostProcessor({
      messageId: "m3",
      userMessage: "Je préfère les réponses courtes",
      assistantMessage: "Noté.",
    });
    expect(result.ok).toBe(true);
    expect(result.changed).toBe(true);
    expect(result.applied).toHaveLength(1);
  });
});
