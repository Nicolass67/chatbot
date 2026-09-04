import { describe, expect, it } from "vitest";
import {
  applyTaintFromToolOutput,
  createTaintState,
  markUntrustedRead,
} from "./taint";

describe("taint tracking", () => {
  it("commence sans taint", () => {
    const state = createTaintState();
    expect(state.untrustedDataRead).toBe(false);
    expect(state.sources).toEqual([]);
  });

  it("marque une source untrusted", () => {
    const state = markUntrustedRead(createTaintState(), "email_get_thread");
    expect(state.untrustedDataRead).toBe(true);
    expect(state.sources).toContain("email_get_thread");
  });

  it("n'duplique pas les sources", () => {
    let state = createTaintState();
    state = markUntrustedRead(state, "web_search");
    state = markUntrustedRead(state, "web_search");
    expect(state.sources).toEqual(["web_search"]);
  });

  it("applique taint depuis output web_search", () => {
    const state = createTaintState();
    const next = applyTaintFromToolOutput(state, "web_search", "output_untrusted");
    expect(next.untrustedDataRead).toBe(true);
  });

  it("ignore taint policy none", () => {
    const state = createTaintState();
    const next = applyTaintFromToolOutput(state, "email_create_draft", "none");
    expect(next.untrustedDataRead).toBe(false);
  });
});
