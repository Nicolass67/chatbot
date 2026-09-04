import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import Database from "better-sqlite3";
import { drizzle, type BetterSQLite3Database } from "drizzle-orm/better-sqlite3";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as schema from "@/lib/db/schema";
import { getActionById } from "@/lib/actions/service";
import {
  getEmailDraftForUser,
  requireEmailDraftForUser,
} from "@/lib/email/draft/service";
import { EmailDraftError } from "@/lib/email/draft/types";
import { getPublicEmailAction } from "@/lib/email/send/service";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";

type TestDb = BetterSQLite3Database<typeof schema>;

let sqlite: Database.Database;
let dbPath: string;
let testDb: TestDb;

function setupSchema(db: Database.Database) {
  db.exec(`
    CREATE TABLE conversations (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL DEFAULT 'Test',
      title_source TEXT NOT NULL DEFAULT 'auto',
      reasoning_effort TEXT,
      chat_mode TEXT NOT NULL DEFAULT 'chat',
      agent_depth TEXT NOT NULL DEFAULT 'standard',
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
  `);
}

vi.mock("@/lib/db", () => ({
  getDb: () => testDb,
}));

describe("email routes auth — isolation utilisateur", () => {
  beforeEach(async () => {
    dbPath = path.join(
      os.tmpdir(),
      `chatbot-email-auth-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
    );
    sqlite = new Database(dbPath);
    setupSchema(sqlite);
    testDb = drizzle(sqlite, { schema });

    sqlite.prepare("INSERT INTO conversations (id) VALUES (?)").run("conv-1");

    await testDb.insert(schema.emailDrafts).values({
      id: "draft-a",
      userId: "user-a",
      conversationId: "conv-1",
      provider: "gmail",
      toJson: '["a@example.com"]',
      contentHash: "hash-a",
      status: "validated",
      subject: "Secret A",
      bodyText: "Corps A",
    });

    const expiresAt = new Date(Date.now() + 30 * 60_000).toISOString();
    await testDb.insert(schema.pendingActions).values({
      id: "action-a",
      userId: "user-a",
      conversationId: "conv-1",
      draftId: "draft-a",
      actionType: "send_email",
      status: "pending_confirmation",
      payloadHash: "hash-a",
      confirmationToken: "secret-confirmation-token",
      expiresAt,
      idempotencyKey: "idem-a",
    });
  });

  afterEach(() => {
    sqlite.close();
    if (fs.existsSync(dbPath)) fs.unlinkSync(dbPath);
  });

  it("user-b ne voit pas le brouillon de user-a", async () => {
    const draft = await getEmailDraftForUser("draft-a", "user-b");
    expect(draft).toBeNull();

    await expect(requireEmailDraftForUser("draft-a", "user-b")).rejects.toBeInstanceOf(
      EmailDraftError
    );
  });

  it("user-b ne récupère pas l'action de user-a", async () => {
    const action = await getActionById("action-a", "user-b");
    expect(action).toBeNull();

    const publicAction = await getPublicEmailAction("action-a", "user-b");
    expect(publicAction).toBeNull();
  });

  it("PublicPendingAction de user-a ne contient pas confirmationToken", async () => {
    const publicAction = await getPublicEmailAction("action-a", "user-a");
    expect(publicAction).not.toBeNull();
    expect(publicAction).not.toHaveProperty("confirmationToken");
    expect(JSON.stringify(publicAction)).not.toContain("secret-confirmation-token");
  });
});

describe("withAuth + apiAuthGuard", () => {
  const originalEnv = { ...process.env };

  afterEach(() => {
    process.env = { ...originalEnv };
  });

  it("401 sans x-user-id quand CF Access exige auth", async () => {
    process.env.CF_ACCESS_ENABLED = "true";
    process.env.CF_ACCESS_TEAM_DOMAIN = "team.cloudflareaccess.com";
    process.env.CF_ACCESS_AUD = "test-aud";

    const handler = withAuth(apiAuthGuard, async () =>
      Response.json({ ok: true })
    );

    const response = await handler(
      new Request("http://localhost/api/email/drafts/x")
    );
    expect(response.status).toBe(401);
  });

  it("200 avec x-user-id en dev", async () => {
    process.env.CF_ACCESS_ENABLED = "false";

    const handler = withAuth(apiAuthGuard, async (_req, auth) =>
      Response.json({ userId: auth.userId })
    );

    const response = await handler(
      new Request("http://localhost/api/test", {
        headers: { "x-user-id": "user-test" },
      })
    );
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ userId: "user-test" });
  });
});
