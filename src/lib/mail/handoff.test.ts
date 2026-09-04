import { describe, expect, it } from "vitest";
import { buildMailHandoffUrl } from "./handoff";

describe("buildMailHandoffUrl", () => {
  it("génère /mail?label=UNREAD pour list non lus implicite", () => {
    const result = buildMailHandoffUrl({ intent: "list", label: "UNREAD" });
    expect(result.url).toBe("/mail?label=UNREAD");
  });

  it("génère /mail?q=... pour search", () => {
    const result = buildMailHandoffUrl({
      intent: "search",
      query: "from:jean@example.com",
    });
    expect(result.url).toBe("/mail?q=from%3Ajean%40example.com");
  });

  it("génère /mail/thread/[id] pour read_thread", () => {
    const result = buildMailHandoffUrl({
      intent: "read_thread",
      threadId: "threadabc123456789",
    });
    expect(result.url).toBe("/mail/thread/threadabc123456789");
  });

  it("sanitise threadId invalide", () => {
    const result = buildMailHandoffUrl({
      intent: "read_thread",
      threadId: "../../../etc/passwd",
    });
    expect(result.url).toBe("/mail");
  });

  it("sanitise label non autorisé", () => {
    const result = buildMailHandoffUrl({
      intent: "list",
      label: "CUSTOM_LABEL",
    });
    expect(result.url).toBe("/mail?label=INBOX");
  });
});
