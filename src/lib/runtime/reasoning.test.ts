import { describe, expect, it } from "vitest";
import {
  buildReasoningCapabilitiesFromNative,
  buildReasoningRequestFields,
  type LmStudioNativeModel,
} from "@/lib/runtime/reasoning";
import {
  resolveReasoningMode,
  normalizeAppDefaultReasoningMode,
} from "@/lib/runtime/reasoning-types";

const qwen35Native: LmStudioNativeModel = {
  type: "llm",
  key: "qwen/qwen3.5-9b",
  display_name: "Qwen3.5 9B",
  capabilities: {
    vision: true,
    trained_for_tool_use: true,
    reasoning: { allowed_options: ["off", "on"], default: "on" },
  },
};

const effortNative: LmStudioNativeModel = {
  type: "llm",
  key: "example/effort-model",
  display_name: "Effort Model",
  capabilities: {
    vision: false,
    trained_for_tool_use: true,
    reasoning: {
      allowed_options: ["off", "low", "medium", "high"],
      default: "medium",
    },
  },
};

describe("buildReasoningCapabilitiesFromNative", () => {
  it("maps Qwen3.5-9B to off/on only", () => {
    const caps = buildReasoningCapabilitiesFromNative(
      "qwen/qwen3.5-9b",
      qwen35Native
    );
    expect(caps.supported).toBe(true);
    expect(caps.kind).toBe("off_on");
    expect(caps.modes.map((m) => m.id)).toEqual(["off", "on"]);
    expect(caps.defaultModeId).toBe("on");
  });

  it("detects effort level models", () => {
    const caps = buildReasoningCapabilitiesFromNative(
      "example/effort-model",
      effortNative
    );
    expect(caps.kind).toBe("effort_levels");
    expect(caps.modes.map((m) => m.id)).toEqual(["off", "low", "medium", "high"]);
  });
});

describe("resolveReasoningMode", () => {
  const qwenCaps = buildReasoningCapabilitiesFromNative(
    "qwen/qwen3.5-9b",
    qwen35Native
  );

  it("maps legacy none to off", () => {
    expect(resolveReasoningMode("none", qwenCaps)).toBe("off");
  });

  it("maps legacy medium to on for off/on models", () => {
    expect(resolveReasoningMode("medium", qwenCaps)).toBe("on");
  });

  it("rejects unsupported legacy xhigh as on", () => {
    expect(resolveReasoningMode("xhigh", qwenCaps)).toBe("on");
  });
});

describe("normalizeAppDefaultReasoningMode", () => {
  it("maps legacy effort levels to on", () => {
    expect(normalizeAppDefaultReasoningMode("medium")).toBe("on");
    expect(normalizeAppDefaultReasoningMode("minimal")).toBe("on");
    expect(normalizeAppDefaultReasoningMode("high")).toBe("on");
  });

  it("maps none to off and keeps on/off", () => {
    expect(normalizeAppDefaultReasoningMode("none")).toBe("off");
    expect(normalizeAppDefaultReasoningMode("on")).toBe("on");
    expect(normalizeAppDefaultReasoningMode("off")).toBe("off");
  });

  it("defaults empty to off", () => {
    expect(normalizeAppDefaultReasoningMode(null)).toBe("off");
    expect(normalizeAppDefaultReasoningMode("")).toBe("off");
  });
});

describe("buildReasoningRequestFields", () => {
  it("omits field for off/none (compat moteurs sans reasoning)", () => {
    expect(buildReasoningRequestFields("off")).toEqual({});
    expect(buildReasoningRequestFields(null)).toEqual({});
    expect(buildReasoningRequestFields(undefined)).toEqual({});
    expect(buildReasoningRequestFields("none")).toEqual({});
  });

  it("omits field for on (model default)", () => {
    expect(buildReasoningRequestFields("on")).toEqual({});
  });

  it("maps effort levels", () => {
    expect(buildReasoningRequestFields("medium")).toEqual({
      reasoning_effort: "medium",
    });
  });
});
