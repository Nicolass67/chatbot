import { describe, expect, it } from "vitest";
import { buildContextWithSnapshot } from "@/lib/context/snapshot";

describe("buildContextWithSnapshot", () => {
  it("computes breakdown reflecting context builder budget", () => {
    const { snapshot } = buildContextWithSnapshot({
      systemPrompt: "Hello",
      memories: [{ id: "1", content: "User likes cats", category: "preference", importance: 0.5, embedding: null, createdAt: "", updatedAt: "" }],
      summary: "Previous chat about pets",
      documentContext: "Doc excerpt",
      toolMessages: [],
      recentMessages: [{ role: "user", content: "Question?" }],
      settings: {
        selectedModel: "test",
        temperature: 0.7,
        maxTokens: 1000,
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
      },
      totalMessageCount: 5,
    });

    expect(snapshot.conversationTokens).toBeGreaterThan(0);
    expect(snapshot.contextLengthMax).toBe(8192);
    expect(snapshot.estimator).toBe("fallback");
    expect(snapshot.breakdown.memories).toBeGreaterThan(0);
    expect(snapshot.breakdown.documents).toBeGreaterThan(0);
    expect(snapshot.totalMessageCount).toBe(5);
  });
});
