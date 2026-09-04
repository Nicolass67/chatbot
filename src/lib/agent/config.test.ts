import { describe, expect, it } from "vitest";
import { resolveAgentLimits } from "./config";
import type { AppSettings } from "@/lib/settings/service";

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

describe("resolveAgentLimits", () => {
  it("lit les limites depuis les paramètres avancés", () => {
    const limits = resolveAgentLimits(baseSettings);
    expect(limits.maxSteps).toBe(12);
    expect(limits.maxToolCalls).toBe(40);
    expect(limits.maxExecutionTimeMs).toBe(300_000);
  });

  it("respecte les surcharges settings", () => {
    const limits = resolveAgentLimits({
      ...baseSettings,
      agentMaxStepsStandard: 20,
      agentMaxToolCalls: 30,
    });
    expect(limits.maxSteps).toBe(20);
    expect(limits.maxToolCalls).toBe(30);
  });
});
