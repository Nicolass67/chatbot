import { describe, expect, it } from "vitest";
import { injectEmailListIntoContext } from "./context-builder";
import type { ChatMessage } from "@/lib/runtime/types";

describe("injectEmailListIntoContext", () => {
  it("injecte des emails réels et interdit l'invention", () => {
    const msgs: ChatMessage[] = [
      { role: "system", content: "Tu es un assistant." },
    ];
    injectEmailListIntoContext(msgs, "Résume mon dernier mail", [
      {
        id: "m1",
        threadId: "t1",
        from: "alice@example.com",
        subject: "Facture mars",
        date: "2026-03-01T10:00:00Z",
        bodyPreview: "Bonjour, voici la facture…",
      },
    ]);
    const content = String(msgs[0]?.content ?? "");
    expect(content).toContain("email_inbox_results");
    expect(content).toContain("Facture mars");
    expect(content).toContain("alice@example.com");
    expect(content).toContain("INTERDIT");
    expect(content).toContain("message n°1");
  });

  it("signale l'absence de résultats sans inventer", () => {
    const msgs: ChatMessage[] = [{ role: "system", content: "sys" }];
    injectEmailListIntoContext(msgs, "inbox", []);
    expect(String(msgs[0]?.content)).toContain("aucun email trouvé");
  });
});
