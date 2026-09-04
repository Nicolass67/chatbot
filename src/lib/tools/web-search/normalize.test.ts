import { describe, expect, it } from "vitest";
import { normalizeWebHits } from "./normalize";

describe("normalizeWebHits", () => {
  it("déduplique par URL et conserve source/publishedAt", () => {
    const hits = [
      {
        title: "A",
        url: "https://example.com/a",
        snippet: "s1",
        source: "google",
        publishedAt: "2026-09-01",
      },
      {
        title: "A duplicate",
        url: "https://example.com/a",
        snippet: "s2",
      },
      {
        title: "B",
        url: "https://example.com/b",
        snippet: "s3",
      },
    ];

    const results = normalizeWebHits(hits, 5);
    expect(results).toHaveLength(2);
    expect(results[0]?.source).toBe("google");
    expect(results[0]?.publishedAt).toBe("2026-09-01");
    expect(results[0]?.domain).toBe("example.com");
  });
});
