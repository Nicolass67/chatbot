import { describe, expect, it } from "vitest";
import { isAbortError } from "./client";

describe("isAbortError", () => {
  it("detects Error named AbortError", () => {
    const err = new Error("aborted");
    err.name = "AbortError";
    expect(isAbortError(err)).toBe(true);
  });

  it("detects DOMException AbortError when available", () => {
    if (typeof DOMException === "undefined") return;
    const err = new DOMException("Aborted", "AbortError");
    expect(isAbortError(err)).toBe(true);
  });

  it("rejects ordinary errors", () => {
    expect(isAbortError(new Error("boom"))).toBe(false);
    expect(isAbortError(null)).toBe(false);
    expect(isAbortError("AbortError")).toBe(false);
  });
});
