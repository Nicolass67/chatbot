import { afterEach, describe, expect, it, vi } from "vitest";
import {
  isExternalHttpUrl,
  openExternal,
  resolveAbsoluteUrl,
} from "./open-external";

describe("open-external", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("resolveAbsoluteUrl joins relative paths with origin", () => {
    vi.stubGlobal("window", {
      location: { origin: "https://chatbot.example" },
    });
    expect(resolveAbsoluteUrl("/api/export")).toBe(
      "https://chatbot.example/api/export"
    );
  });

  it("isExternalHttpUrl detects other origins", () => {
    vi.stubGlobal("window", {
      location: { origin: "https://chatbot.example" },
    });
    expect(isExternalHttpUrl("https://example.com/x")).toBe(true);
    expect(isExternalHttpUrl("/chat/new")).toBe(false);
  });

  it("openExternal uses window.open on web", async () => {
    const open = vi.fn();
    vi.stubGlobal("window", {
      location: { origin: "https://chatbot.example" },
      open,
    });
    await openExternal("https://example.com");
    expect(open).toHaveBeenCalledWith(
      "https://example.com/",
      "_blank",
      "noopener,noreferrer"
    );
  });
});
