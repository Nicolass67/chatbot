import { describe, expect, it } from "vitest";
import { compressToolResultForContext } from "@/lib/context/tool-result-compress";

describe("compressToolResultForContext", () => {
  it("keeps error fields and truncates large content", () => {
    const out = compressToolResultForContext(
      {
        ok: false,
        error: "timeout",
        content: "x".repeat(5000),
      },
      { maxChars: 800 }
    );
    expect(out).toContain("timeout");
    expect(out.length).toBeLessThanOrEqual(800);
  });

  it("caps web results array", () => {
    const out = JSON.parse(
      compressToolResultForContext({
        results: Array.from({ length: 20 }, (_, i) => ({
          title: `t${i}`,
          url: `https://ex.com/${i}`,
          snippet: "s".repeat(400),
        })),
      })
    ) as { results: unknown[]; resultsOmitted?: number; truncated?: boolean };
    expect(out.results?.length ?? 0).toBeLessThanOrEqual(8);
    expect((out.resultsOmitted ?? 0) + (out.results?.length ?? 0)).toBeGreaterThanOrEqual(8);
  });
});
