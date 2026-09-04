import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import Database from "better-sqlite3";
import { drizzle, type BetterSQLite3Database } from "drizzle-orm/better-sqlite3";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as schema from "@/lib/db/schema";
import {
  cancelEmailDraft,
  persistEmailDraft,
  updateEmailDraft,
  validateEmailDraft,
} from "./service";

type TestDb = BetterSQLite3Database<typeof schema>;

let sqlite: Database.Database;
let dbPath: string;
let testDb: TestDb;

function setupSchema(db: Database.Database) {
  db.exec(`
    CREATE TABLE conversations (
      id TEXT PRIMARY KEY,
      title TEXT,
      chat_mode TEXT DEFAULT 'chat',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE email_drafts (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      conversation_id TEXT NOT NULL,
      thread_id TEXT,
      provider TEXT NOT NULL,
      provider_draft_id TEXT,
      to_json TEXT NOT NULL DEFAULT '[]',
      cc_json TEXT NOT NULL DEFAULT '[]',
      bcc_json TEXT NOT NULL DEFAULT '[]',
      subject TEXT NOT NULL DEFAULT '',
      body_text TEXT NOT NULL DEFAULT '',
      body_html TEXT,
      attachment_ids_json TEXT NOT NULL DEFAULT '[]',
      content_hash TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'draft',
      in_reply_to_message_id TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);
}

vi.mock("@/lib/db", () => ({
  getDb: () => testDb,
}));

describe("email draft service", () => {
  beforeEach(() => {
    dbPath = path.join(
      os.tmpdir(),
      `chatbot-draft-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
    );
    sqlite = new Database(dbPath);
    setupSchema(sqlite);
    sqlite.prepare("INSERT INTO conversations (id) VALUES (?)").run("conv-1");
    testDb = drizzle(sqlite, { schema });
  });

  afterEach(() => {
    sqlite.close();
    if (fs.existsSync(dbPath)) fs.unlinkSync(dbPath);
  });

  it("persist puis validate met le statut validated", async () => {
    const draft = await persistEmailDraft({
      userId: "user-1",
      conversationId: "conv-1",
      provider: "gmail",
      to: ["a@example.com"],
      subject: "Sujet",
      bodyText: "Corps",
    });

    expect(draft.status).toBe("draft");

    const validated = await validateEmailDraft(draft.id, "user-1");
    expect(validated.status).toBe("validated");
  });

  it("update repasse validated → draft et recalcule le hash", async () => {
    const draft = await persistEmailDraft({
      userId: "user-1",
      conversationId: "conv-1",
      provider: "gmail",
      to: ["a@example.com"],
      subject: "Sujet",
      bodyText: "Corps",
    });

    await validateEmailDraft(draft.id, "user-1");
    const updated = await updateEmailDraft(draft.id, "user-1", {
      bodyText: "Corps modifié",
    });

    expect(updated.status).toBe("draft");
    expect(updated.bodyText).toBe("Corps modifié");
    expect(updated.contentHash).not.toBe(draft.contentHash);
  });

  it("cancel marque le brouillon annulé", async () => {
    const draft = await persistEmailDraft({
      userId: "user-1",
      conversationId: "conv-1",
      provider: "gmail",
      to: ["a@example.com"],
      subject: "Sujet",
      bodyText: "Corps",
    });

    const cancelled = await cancelEmailDraft(draft.id, "user-1");
    expect(cancelled.status).toBe("cancelled");
  });
});
