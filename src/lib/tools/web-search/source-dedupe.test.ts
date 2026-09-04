import { describe, expect, it } from "vitest";
import {
  canonicalizeUrl,
  dedupeAndCapSources,
  mergeUniqueSources,
} from "./source-dedupe";
import type { SearchResult } from "../types";

function hit(url: string, title = "t"): SearchResult {
  return {
    title,
    url,
    domain: "example.com",
    snippet: "s",
  };
}

describe("source-dedupe", () => {
  it("canonise www, trailing slash et utm", () => {
    expect(
      canonicalizeUrl("https://www.Example.com/path/?utm_source=x#frag")
    ).toBe("https://example.com/path");
  });

  it("fusionne sans doublons canoniques", () => {
    const target: SearchResult[] = [];
    const added = mergeUniqueSources(target, [
      hit("https://www.example.com/a"),
      hit("https://example.com/a/"),
      hit("https://example.com/b"),
    ]);
    expect(added).toBe(2);
    expect(target).toHaveLength(2);
  });

  it("plafonne le total", () => {
    const target: SearchResult[] = [];
    mergeUniqueSources(
      target,
      [hit("https://a.com/1"), hit("https://a.com/2"), hit("https://a.com/3")],
      { maxTotal: 2 }
    );
    expect(target).toHaveLength(2);
    expect(dedupeAndCapSources(target, 1)).toHaveLength(1);
  });
});
