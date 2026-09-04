import { describe, expect, it } from "vitest";
import { getRegisteredTools, getTool, getToolDefinitions } from "./registry";

describe("tool registry V2", () => {
  it("n'expose plus les email tools au chat LLM", () => {
    const tools = getRegisteredTools({
      webSearchEnabled: false,
      emailEnabled: true,
    }).map((t) => t.name);

    expect(tools).toEqual([]);
  });

  it("n'expose pas email_send au LLM", () => {
    const names = getToolDefinitions({
      webSearchEnabled: true,
      emailEnabled: true,
    }).map((d) => d.function.name);

    expect(names).not.toContain("email_send");
    expect(names).not.toContain("email_list");
    expect(names).toContain("web_search");
  });

  it("email_send reste disponible en interne via getTool", () => {
    expect(getTool("email_send")).toBeDefined();
    const names = getRegisteredTools({
      webSearchEnabled: true,
      emailEnabled: true,
    }).map((t) => t.name);
    expect(names).not.toContain("email_send");
  });
});
