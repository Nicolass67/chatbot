import { describe, expect, it } from "vitest";
import { getRegisteredTools, getTool, getToolDefinitions } from "./registry";

describe("tool registry V2", () => {
  it("n'expose plus les email tools au chat LLM sans candidats", () => {
    const tools = getRegisteredTools({
      webSearchEnabled: false,
      emailEnabled: true,
    }).map((t) => t.name);

    expect(tools).toEqual([]);
  });

  it("expose les email tools mail-scope via candidats explicites", () => {
    const tools = getRegisteredTools({
      webSearchEnabled: false,
      emailEnabled: true,
      emailToolCandidates: ["email_create_draft", "email_get_thread"],
    }).map((t) => t.name);

    expect(tools).toContain("email_create_draft");
    expect(tools).toContain("email_get_thread");
    expect(tools).not.toContain("email_send");
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

  it("n'expose plus les file tools au LLM sans candidats", () => {
    const tools = getRegisteredTools({
      webSearchEnabled: true,
      filesEnabled: true,
    }).map((t) => t.name);

    expect(tools).toEqual(["web_search"]);
    expect(tools).not.toContain("file_search");
  });

  it("expose file_search uniquement via candidats explicites", () => {
    const tools = getRegisteredTools({
      webSearchEnabled: true,
      filesEnabled: true,
      fileToolCandidates: ["file_search"],
    }).map((t) => t.name);

    expect(tools).toContain("web_search");
    expect(tools).toContain("file_search");
    expect(tools).not.toContain("file_list");
  });
});
