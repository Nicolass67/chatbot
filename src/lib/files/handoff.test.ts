import { describe, expect, it } from "vitest";
import {
  buildFilesHandoffUrl,
  resolveFilesHandoffHref,
} from "./handoff";

describe("buildFilesHandoffUrl", () => {
  it("génère query intent+q+root", () => {
    const result = buildFilesHandoffUrl({
      intent: "search",
      query: "facture",
      rootId: "rootabcd12",
    });
    expect(result.rootId).toBe("rootabcd12");
    expect(result.url).toBe(
      "/files?intent=search&q=facture&root=rootabcd12"
    );
  });

  it("sanitise rootId invalide", () => {
    const result = buildFilesHandoffUrl({
      intent: "list",
      rootId: "../etc",
    });
    expect(result.rootId).toBeUndefined();
    expect(resolveFilesHandoffHref(result)).toBe("/files?intent=list");
  });
});
