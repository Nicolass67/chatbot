import { describe, expect, it } from "vitest";
import { serializeModelRuntimeState } from "./model-state";

describe("serializeModelRuntimeState", () => {
  it("expose currentModel comme alias de loadedModel", () => {
    const serialized = serializeModelRuntimeState({
      phase: "ready",
      preferredModel: "model-a",
      loadedModel: "model-a",
      targetModel: null,
      pendingRequestCount: 0,
      message: "OK",
    });

    expect(serialized.currentModel).toBe("model-a");
    expect(serialized.loadedModel).toBe("model-a");
    expect(serialized.phase).toBe("ready");
    expect(serialized.message).toBe("OK");
  });
});
