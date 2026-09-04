import { describe, expect, it } from "vitest";
import { stabilizeStreamingMarkdown } from "@/components/markdown/stabilize-streaming";

describe("stabilizeStreamingMarkdown", () => {
  it("closes an unclosed fenced code block", () => {
    const input = "Text\n```typescript\nconst x = 1;";
    const result = stabilizeStreamingMarkdown(input);
    expect(result).toContain("```typescript\nconst x = 1;\n```");
  });

  it("does not add extra fences when already balanced", () => {
    const input = "```js\nok\n```";
    expect(stabilizeStreamingMarkdown(input)).toBe(input);
  });

  it("leaves incomplete bold markers unchanged", () => {
    const input = "**Bonjour";
    expect(stabilizeStreamingMarkdown(input)).toBe(input);
  });
});
