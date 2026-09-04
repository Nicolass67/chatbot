import { describe, expect, it } from "vitest";
import { chunkText, normalizeText } from "@/lib/attachments/extract";

describe("chunkText", () => {
  it("returns empty for blank input", () => {
    expect(chunkText("   ")).toEqual([]);
  });

  it("keeps short text as single chunk", () => {
    const text = "Hello world";
    expect(chunkText(text)).toEqual([text]);
  });

  it("splits long text into multiple chunks", () => {
    const text = "word ".repeat(500).trim();
    const chunks = chunkText(text);
    expect(chunks.length).toBeGreaterThan(1);
    expect(chunks.join(" ").length).toBeGreaterThan(text.length * 0.8);
  });

  it("normalizes whitespace", () => {
    expect(normalizeText("a\r\n\r\n\r\nb")).toBe("a\n\nb");
  });
});
