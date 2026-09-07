import { describe, expect, it } from "vitest";
import { formatActiveContextBlock } from "@/lib/context/active-context";

describe("formatActiveContextBlock", () => {
  it("injecte le corps du mail dans le prompt", () => {
    const block = formatActiveContextBlock({
      hint: { mailThreadId: "t1" },
      resolved: true,
      entityLabels: ["Sujet test"],
      mail: {
        threadId: "t1",
        subject: "Sujet test",
        from: "Alice <alice@example.com>",
        date: "2026-09-04",
        bodyForLlm: "Bonjour, peux-tu confirmer la réunion ?",
        attachmentNames: ["agenda.pdf"],
      },
    });

    expect(block).toContain("<active_context>");
    expect(block).toContain("threadId=t1");
    expect(block).toContain("<email_context");
    expect(block).toContain("Bonjour, peux-tu confirmer la réunion ?");
    expect(block).toContain("agenda.pdf");
  });

  it("ne prétend pas resolved sans entité", () => {
    expect(
      formatActiveContextBlock({
        hint: {},
        resolved: false,
        entityLabels: [],
      })
    ).toBeNull();
  });

  it("expose le brouillon ouvert sans fil mail", () => {
    const block = formatActiveContextBlock({
      hint: { draftId: "d1" },
      resolved: true,
      entityLabels: ["Re: CI"],
      draft: {
        draftId: "d1",
        subject: "Re: CI",
        to: ["notifications@example.com"],
      },
    });
    expect(block).toContain("draftId=d1");
    expect(block).toContain("ne demande JAMAIS");
    expect(block).toContain("Re: CI");
    expect(block).toContain("notifications@example.com");
  });
});
