import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/lm-studio/client", () => ({
  lmStudioGetModels: vi.fn(),
}));

vi.mock("@/lib/runtime/reasoning", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/runtime/reasoning")>();
  return {
    ...actual,
    lmStudioGetNativeModels: vi.fn(),
    getReasoningCapabilities: vi.fn(),
  };
});

import { lmStudioGetModels } from "@/lib/lm-studio/client";
import {
  getReasoningCapabilities,
  lmStudioGetNativeModels,
} from "@/lib/runtime/reasoning";
import { getActiveModelCapabilities } from "@/lib/runtime/capabilities";

const noReasoning = {
  modelId: "qwen/qwen3.5-9b",
  supported: false,
  kind: "none" as const,
  modes: [],
  defaultModeId: null,
  transmissionMethod: null,
  source: "unknown" as const,
};

describe("getActiveModelCapabilities", () => {
  beforeEach(() => {
    vi.mocked(lmStudioGetModels).mockResolvedValue([
      { id: "qwen/qwen3.5-9b", name: "Qwen3.5 9B" },
    ]);
    vi.mocked(getReasoningCapabilities).mockResolvedValue(noReasoning);
  });

  it("uses LM Studio native vision flag when name heuristics miss", async () => {
    vi.mocked(lmStudioGetNativeModels).mockResolvedValue([
      {
        type: "llm",
        key: "qwen/qwen3.5-9b",
        display_name: "Qwen3.5 9B",
        capabilities: {
          vision: true,
          trained_for_tool_use: true,
        },
      },
    ]);

    const caps = await getActiveModelCapabilities("qwen/qwen3.5-9b");
    expect(caps.capabilities.vision).toBe(true);
    expect(caps.source).toBe("lm_studio_api");
  });

  it("keeps vision false when native and heuristics both deny", async () => {
    vi.mocked(lmStudioGetNativeModels).mockResolvedValue([
      {
        type: "llm",
        key: "qwen/qwen3-8b",
        display_name: "Qwen3 8B",
        capabilities: {
          vision: false,
          trained_for_tool_use: true,
        },
      },
    ]);

    const caps = await getActiveModelCapabilities("qwen/qwen3-8b");
    expect(caps.capabilities.vision).toBe(false);
  });
});
