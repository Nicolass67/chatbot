import { describe, expect, it } from "vitest";
import {
  formatModelCompactName,
  formatModelFullName,
} from "./display-name";

describe("formatModelDisplayName", () => {
  it("normalise le nom complet", () => {
    expect(
      formatModelFullName(
        "Bucoid/Qwen3.8-27B/Qwen3.8-27B-IQ4_XS_4BPW.gguf"
      )
    ).toBe("Qwen3.8 27B IQ4 XS 4BPW");
  });

  it("compacte base + quant", () => {
    expect(formatModelCompactName("Qwen3.8-27B-IQ4_XS_4BPW")).toBe(
      "Qwen3.8-27B · IQ4"
    );
  });

  it("laisse les noms courts intacts", () => {
    expect(formatModelCompactName("llama-3.2-3b")).toBe("llama 3.2 3b");
  });

  it("gère un chemin publisher/repo/file", () => {
    expect(
      formatModelCompactName(
        "Bucoid/Qwen3.8-27B/Qwen3.8-27B-IQ4_XS_4BPW"
      )
    ).toBe("Qwen3.8-27B · IQ4");
  });
});
