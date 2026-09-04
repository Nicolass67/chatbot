import { describe, expect, it } from "vitest";
import {
  buildGmailListQuery,
  buildGmailRawMessage,
  normalizeGmailMessage,
  normalizeGmailThread,
} from "./normalizer";

describe("gmail normalizer", () => {
  it("normalizeGmailMessage parse headers et corps texte", () => {
    const bodyText = "Bonjour, ceci est un test.";
    const rawBody = Buffer.from(bodyText, "utf8").toString("base64url");

    const message = normalizeGmailMessage({
      id: "msg-1",
      threadId: "thread-1",
      snippet: "Bonjour, ceci",
      labelIds: ["INBOX", "UNREAD"],
      payload: {
        headers: [
          { name: "From", value: "Alice <alice@example.com>" },
          { name: "To", value: "bob@example.com" },
          { name: "Subject", value: "Test sujet" },
          { name: "Date", value: "Mon, 1 Sep 2025 10:00:00 +0000" },
        ],
        mimeType: "text/plain",
        body: { data: rawBody },
      },
    });

    expect(message.id).toBe("msg-1");
    expect(message.from).toEqual({ email: "alice@example.com", name: "Alice" });
    expect(message.to).toEqual([{ email: "bob@example.com" }]);
    expect(message.subject).toBe("Test sujet");
    expect(message.bodyText).toBe(bodyText);
    expect(message.isUnread).toBe(true);
    expect(message.hasAttachments).toBe(false);
  });

  it("normalizeGmailMessage extrait les pièces jointes", () => {
    const message = normalizeGmailMessage({
      id: "msg-2",
      threadId: "thread-1",
      payload: {
        headers: [{ name: "From", value: "a@example.com" }],
        parts: [
          {
            mimeType: "text/plain",
            body: {
              data: Buffer.from("texte", "utf8").toString("base64url"),
            },
          },
          {
            filename: "doc.pdf",
            mimeType: "application/pdf",
            body: { attachmentId: "att-1", size: 1024 },
          },
        ],
      },
    });

    expect(message.hasAttachments).toBe(true);
    expect(message.attachments).toEqual([
      {
        id: "att-1",
        filename: "doc.pdf",
        mimeType: "application/pdf",
        sizeBytes: 1024,
      },
    ]);
  });

  it("normalizeGmailThread agrège messages et participants", () => {
    const thread = normalizeGmailThread({
      id: "thread-1",
      messages: [
        {
          id: "m1",
          threadId: "thread-1",
          payload: {
            headers: [
              { name: "From", value: "alice@example.com" },
              { name: "To", value: "bob@example.com" },
              { name: "Subject", value: "Projet" },
            ],
          },
        },
        {
          id: "m2",
          threadId: "thread-1",
          payload: {
            headers: [
              { name: "From", value: "bob@example.com" },
              { name: "To", value: "alice@example.com" },
            ],
          },
        },
      ],
    });

    expect(thread.id).toBe("thread-1");
    expect(thread.subject).toBe("Projet");
    expect(thread.messages).toHaveLength(2);
    expect(thread.participants.map((p) => p.email).sort()).toEqual([
      "alice@example.com",
      "bob@example.com",
    ]);
  });

  it("buildGmailRawMessage encode un message RFC minimal", () => {
    const raw = buildGmailRawMessage({
      to: ["dest@example.com"],
      subject: "Hello",
      bodyText: "Contenu",
    });
    const decoded = Buffer.from(
      raw.replace(/-/g, "+").replace(/_/g, "/"),
      "base64"
    ).toString("utf8");

    expect(decoded).toContain("To: dest@example.com");
    expect(decoded).toContain("Subject: Hello");
    expect(decoded).toContain("Content-Transfer-Encoding: base64");
    expect(decoded).toContain(
      Buffer.from("Contenu", "utf8").toString("base64")
    );
  });

  it("buildGmailRawMessage encode multipart avec pièce jointe", () => {
    const fileB64 = Buffer.from("fichier-test", "utf8").toString("base64");
    const raw = buildGmailRawMessage({
      to: ["dest@example.com"],
      subject: "Avec PJ",
      bodyText: "Voir PJ",
      attachments: [
        {
          filename: "note.txt",
          mimeType: "text/plain",
          contentBase64: fileB64,
        },
      ],
    });
    const decoded = Buffer.from(
      raw.replace(/-/g, "+").replace(/_/g, "/"),
      "base64"
    ).toString("utf8");

    expect(decoded).toContain("multipart/mixed");
    expect(decoded).toContain('filename="note.txt"');
    expect(decoded).toContain(fileB64);
  });

  it("buildGmailListQuery combine query et after", () => {
    expect(
      buildGmailListQuery({
        query: "from:boss@corp.com",
        after: "2025-09-01",
      })
    ).toBe("from:boss@corp.com after:2025/09/01");
    expect(buildGmailListQuery({})).toBeUndefined();
  });
});
