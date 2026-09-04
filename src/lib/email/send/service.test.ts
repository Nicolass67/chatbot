import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import Database from "better-sqlite3";
import { drizzle, type BetterSQLite3Database } from "drizzle-orm/better-sqlite3";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as schema from "@/lib/db/schema";
import {
  cancelEmailSendAction,
  confirmAndExecuteEmailSend,
  proposeEmailSend,
} from "./service";

vi.mock("@/lib/tools/execute-with-policy", () => ({
  executeToolWithPolicy: vi.fn(async () => ({
    draftId: "draft-1",
    messageId: "msg-sent",
    threadId: "thread-sent",
  })),
}));

vi.mock("@/lib/tools/policy-context", () => ({
  resolveEmailPolicyContext: vi.fn(async () => ({
    emailConnected: true,
    grantedPermissions: ["SEND_EMAIL", "READ_EMAIL", "CREATE_DRAFT"],
  })),
}));

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
    CREATE TABLE pending_actions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      conversation_id TEXT NOT NULL,
      draft_id TEXT,
      resource_id TEXT,
      action_type TEXT NOT NULL,
      status TEXT NOT NULL,
      payload_hash TEXT NOT NULL,
      confirmation_token TEXT NOT NULL UNIQUE,
      expires_at TEXT NOT NULL,
      confirmed_at TEXT,
      executed_at TEXT,
      idempotency_key TEXT NOT NULL UNIQUE,
      error_code TEXT,
      error_message TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE action_audit_log (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      action_type TEXT NOT NULL,
      resource_type TEXT NOT NULL,
      resource_id TEXT NOT NULL,
      status TEXT NOT NULL,
      metadata_json TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);
}

vi.mock("@/lib/db", () => ({
  getDb: () => testDb,
}));

const baseSettings = {} as import("@/lib/settings/service").AppSettings;

describe("email send service", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    dbPath = path.join(
      os.tmpdir(),
      `chatbot-send-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
    );
    sqlite = new Database(dbPath);
    setupSchema(sqlite);
    sqlite.prepare("INSERT INTO conversations (id) VALUES (?)").run("conv-1");
    testDb = drizzle(sqlite, { schema });

    sqlite.prepare(`
      INSERT INTO email_drafts (
        id, user_id, conversation_id, provider, provider_draft_id,
        to_json, cc_json, bcc_json, subject, body_text, content_hash, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      "draft-1",
      "user-1",
      "conv-1",
      "gmail",
      "gmail-draft-1",
      '["dest@example.com"]',
      "[]",
      "[]",
      "Sujet",
      "Corps",
      "hash-validated",
      "validated"
    );
  });

  afterEach(() => {
    sqlite.close();
    if (fs.existsSync(dbPath)) fs.unlinkSync(dbPath);
  });

  it("proposeEmailSend crée une action pending_confirmation", async () => {
    const proposal = await proposeEmailSend({
      userId: "user-1",
      draftId: "draft-1",
    });

    expect(proposal.status).toBe("pending_confirmation");
    expect(proposal.confirmationToken.length).toBeGreaterThan(10);
  });

  it("confirmAndExecuteEmailSend envoie et marque completed", async () => {
    const proposal = await proposeEmailSend({
      userId: "user-1",
      draftId: "draft-1",
    });

    const result = await confirmAndExecuteEmailSend({
      actionId: proposal.actionId,
      confirmationToken: proposal.confirmationToken,
      userId: "user-1",
      settings: baseSettings,
      conversationId: "conv-1",
    });

    expect(result.status).toBe("completed");
    expect(result.messageId).toBe("msg-sent");

    const draft = sqlite
      .prepare("SELECT status FROM email_drafts WHERE id = ?")
      .get("draft-1") as { status: string };
    expect(draft.status).toBe("sent");
  });

  it("cancelEmailSendAction annule une action pending", async () => {
    const proposal = await proposeEmailSend({
      userId: "user-1",
      draftId: "draft-1",
    });

    const cancelled = await cancelEmailSendAction(
      proposal.actionId,
      "user-1"
    );
    expect(cancelled.status).toBe("cancelled");
  });
});
