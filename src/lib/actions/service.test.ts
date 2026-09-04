import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import Database from "better-sqlite3";
import { drizzle, type BetterSQLite3Database } from "drizzle-orm/better-sqlite3";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as schema from "@/lib/db/schema";
import { PolicyDeniedError } from "@/lib/policy";
import {
  cancelAction,
  confirmSendAction,
  createSendConfirmationAction,
  expireStaleActions,
  getPendingSendActionForConversation,
  markActionCompleted,
  markActionFailed,
} from "./service";
import { ActionError } from "./types";

type TestDb = BetterSQLite3Database<typeof schema>;

let sqlite: Database.Database;
let dbPath: string;
let testDb: TestDb;

function setupSchema(db: Database.Database) {
  db.exec(`
    CREATE TABLE conversations (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL DEFAULT 'Nouvelle conversation',
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
      conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
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
      conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      draft_id TEXT REFERENCES email_drafts(id) ON DELETE SET NULL,
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

async function seedDraft(params: {
  draftId: string;
  userId: string;
  conversationId: string;
  contentHash: string;
  status?: "draft" | "validated";
}) {
  await testDb.insert(schema.conversations).values({
    id: params.conversationId,
    title: "Test",
  });

  await testDb.insert(schema.emailDrafts).values({
    id: params.draftId,
    userId: params.userId,
    conversationId: params.conversationId,
    provider: "gmail",
    toJson: JSON.stringify(["jean@example.com"]),
    contentHash: params.contentHash,
    status: params.status ?? "validated",
    subject: "Re: Test",
    bodyText: "Bonjour",
  });
}

vi.mock("@/lib/db", () => ({
  getDb: () => testDb,
}));

describe("action service", () => {
  beforeEach(() => {
    dbPath = path.join(
      os.tmpdir(),
      `chatbot-actions-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
    );
    sqlite = new Database(dbPath);
    sqlite.pragma("foreign_keys = ON");
    setupSchema(sqlite);
    testDb = drizzle(sqlite, { schema });
  });

  afterEach(() => {
    sqlite.close();
    if (fs.existsSync(dbPath)) fs.unlinkSync(dbPath);
  });

  it("crée une action send_email en pending_confirmation", async () => {
    await seedDraft({
      draftId: "draft-1",
      userId: "user-1",
      conversationId: "conv-1",
      contentHash: "hash-1",
    });

    const action = await createSendConfirmationAction({
      userId: "user-1",
      conversationId: "conv-1",
      draftId: "draft-1",
      payloadHash: "hash-1",
    });

    expect(action.status).toBe("pending_confirmation");
    expect(action.confirmationToken.length).toBeGreaterThan(10);
  });

  it("refuse création si brouillon non validé", async () => {
    await seedDraft({
      draftId: "draft-1",
      userId: "user-1",
      conversationId: "conv-1",
      contentHash: "hash-1",
      status: "draft",
    });

    await expect(
      createSendConfirmationAction({
        userId: "user-1",
        conversationId: "conv-1",
        draftId: "draft-1",
        payloadHash: "hash-1",
      })
    ).rejects.toMatchObject({ code: "DRAFT_NOT_VALIDATED" });
  });

  it("confirme une action valide → executing", async () => {
    await seedDraft({
      draftId: "draft-1",
      userId: "user-1",
      conversationId: "conv-1",
      contentHash: "hash-1",
    });

    const created = await createSendConfirmationAction({
      userId: "user-1",
      conversationId: "conv-1",
      draftId: "draft-1",
      payloadHash: "hash-1",
    });

    const confirmed = await confirmSendAction({
      actionId: created.id,
      confirmationToken: created.confirmationToken,
      userId: "user-1",
      emailConnected: true,
      grantedPermissions: ["SEND_EMAIL", "READ_EMAIL", "CREATE_DRAFT"],
    });

    expect(confirmed.status).toBe("executing");
  });

  it("refuse confirmation avec mauvais userId", async () => {
    await seedDraft({
      draftId: "draft-1",
      userId: "user-1",
      conversationId: "conv-1",
      contentHash: "hash-1",
    });

    const created = await createSendConfirmationAction({
      userId: "user-1",
      conversationId: "conv-1",
      draftId: "draft-1",
      payloadHash: "hash-1",
    });

    await expect(
      confirmSendAction({
        actionId: created.id,
        confirmationToken: created.confirmationToken,
        userId: "attacker",
        emailConnected: true,
        grantedPermissions: ["SEND_EMAIL"],
      })
    ).rejects.toBeInstanceOf(ActionError);
  });

  it("refuse double confirmation", async () => {
    await seedDraft({
      draftId: "draft-1",
      userId: "user-1",
      conversationId: "conv-1",
      contentHash: "hash-1",
    });

    const created = await createSendConfirmationAction({
      userId: "user-1",
      conversationId: "conv-1",
      draftId: "draft-1",
      payloadHash: "hash-1",
    });

    const input = {
      actionId: created.id,
      confirmationToken: created.confirmationToken,
      userId: "user-1",
      emailConnected: true,
      grantedPermissions: ["SEND_EMAIL", "READ_EMAIL", "CREATE_DRAFT"] as const,
    };

    await confirmSendAction({
      ...input,
      grantedPermissions: [...input.grantedPermissions],
    });

    await expect(
      confirmSendAction({
        ...input,
        grantedPermissions: [...input.grantedPermissions],
      })
    ).rejects.toMatchObject({ code: "ALREADY_USED" });
  });

  it("refuse confirmation expirée", async () => {
    await seedDraft({
      draftId: "draft-1",
      userId: "user-1",
      conversationId: "conv-1",
      contentHash: "hash-1",
    });

    const created = await createSendConfirmationAction({
      userId: "user-1",
      conversationId: "conv-1",
      draftId: "draft-1",
      payloadHash: "hash-1",
    });

    sqlite
      .prepare(`UPDATE pending_actions SET expires_at = ? WHERE id = ?`)
      .run(new Date(Date.now() - 60_000).toISOString(), created.id);

    await expect(
      confirmSendAction({
        actionId: created.id,
        confirmationToken: created.confirmationToken,
        userId: "user-1",
        emailConnected: true,
        grantedPermissions: ["SEND_EMAIL"],
      })
    ).rejects.toMatchObject({ code: "EXPIRED" });
  });

  it("refuse SEND sans permission OAuth", async () => {
    await seedDraft({
      draftId: "draft-1",
      userId: "user-1",
      conversationId: "conv-1",
      contentHash: "hash-1",
    });

    const created = await createSendConfirmationAction({
      userId: "user-1",
      conversationId: "conv-1",
      draftId: "draft-1",
      payloadHash: "hash-1",
    });

    await expect(
      confirmSendAction({
        actionId: created.id,
        confirmationToken: created.confirmationToken,
        userId: "user-1",
        emailConnected: false,
        grantedPermissions: [],
      })
    ).rejects.toBeInstanceOf(PolicyDeniedError);
  });

  it("annule une action pending", async () => {
    await seedDraft({
      draftId: "draft-1",
      userId: "user-1",
      conversationId: "conv-1",
      contentHash: "hash-1",
    });

    const created = await createSendConfirmationAction({
      userId: "user-1",
      conversationId: "conv-1",
      draftId: "draft-1",
      payloadHash: "hash-1",
    });

    const cancelled = await cancelAction(created.id, "user-1");
    expect(cancelled.status).toBe("cancelled");
  });

  it("finalise executing → completed et marque le draft sent", async () => {
    await seedDraft({
      draftId: "draft-1",
      userId: "user-1",
      conversationId: "conv-1",
      contentHash: "hash-1",
    });

    const created = await createSendConfirmationAction({
      userId: "user-1",
      conversationId: "conv-1",
      draftId: "draft-1",
      payloadHash: "hash-1",
    });

    const executing = await confirmSendAction({
      actionId: created.id,
      confirmationToken: created.confirmationToken,
      userId: "user-1",
      emailConnected: true,
      grantedPermissions: ["SEND_EMAIL", "READ_EMAIL", "CREATE_DRAFT"],
    });

    const completed = await markActionCompleted(executing.id, "user-1");
    expect(completed.status).toBe("completed");

    const draft = await testDb.query.emailDrafts.findFirst({
      where: (d, { eq }) => eq(d.id, "draft-1"),
    });
    expect(draft?.status).toBe("sent");
  });

  it("expire les actions stale en batch", async () => {
    await seedDraft({
      draftId: "draft-1",
      userId: "user-1",
      conversationId: "conv-1",
      contentHash: "hash-1",
    });

    const created = await createSendConfirmationAction({
      userId: "user-1",
      conversationId: "conv-1",
      draftId: "draft-1",
      payloadHash: "hash-1",
    });

    sqlite
      .prepare(`UPDATE pending_actions SET expires_at = ? WHERE id = ?`)
      .run(new Date(Date.now() - 60_000).toISOString(), created.id);

    const count = await expireStaleActions();
    expect(count).toBe(1);

    const pending = await getPendingSendActionForConversation("conv-1", "user-1");
    expect(pending).toBeNull();
  });

  it("marque une action en échec depuis executing", async () => {
    await seedDraft({
      draftId: "draft-1",
      userId: "user-1",
      conversationId: "conv-1",
      contentHash: "hash-1",
    });

    const created = await createSendConfirmationAction({
      userId: "user-1",
      conversationId: "conv-1",
      draftId: "draft-1",
      payloadHash: "hash-1",
    });

    const executing = await confirmSendAction({
      actionId: created.id,
      confirmationToken: created.confirmationToken,
      userId: "user-1",
      emailConnected: true,
      grantedPermissions: ["SEND_EMAIL", "READ_EMAIL", "CREATE_DRAFT"],
    });

    const failed = await markActionFailed(
      executing.id,
      "user-1",
      "PROVIDER_ERROR",
      "Gmail indisponible"
    );
    expect(failed.status).toBe("failed");
    expect(failed.errorCode).toBe("PROVIDER_ERROR");
  });

  it("createSendConfirmationAction est idempotent pour la même clé", async () => {
    await seedDraft({
      draftId: "draft-1",
      userId: "user-1",
      conversationId: "conv-1",
      contentHash: "hash-1",
    });

    const first = await createSendConfirmationAction({
      userId: "user-1",
      conversationId: "conv-1",
      draftId: "draft-1",
      payloadHash: "hash-1",
    });

    const second = await createSendConfirmationAction({
      userId: "user-1",
      conversationId: "conv-1",
      draftId: "draft-1",
      payloadHash: "hash-1",
    });

    expect(second.id).toBe(first.id);
    expect(second.confirmationToken).toBe(first.confirmationToken);

    const count = sqlite
      .prepare("SELECT COUNT(*) AS c FROM pending_actions")
      .get() as { c: number };
    expect(count.c).toBe(1);
  });

  it("écrit des lignes action_audit_log aux transitions clés", async () => {
    await seedDraft({
      draftId: "draft-1",
      userId: "user-1",
      conversationId: "conv-1",
      contentHash: "hash-1",
    });

    const created = await createSendConfirmationAction({
      userId: "user-1",
      conversationId: "conv-1",
      draftId: "draft-1",
      payloadHash: "hash-1",
    });

    let auditCount = (
      sqlite.prepare("SELECT COUNT(*) AS c FROM action_audit_log").get() as {
        c: number;
      }
    ).c;
    expect(auditCount).toBeGreaterThanOrEqual(1);

    const executing = await confirmSendAction({
      actionId: created.id,
      confirmationToken: created.confirmationToken,
      userId: "user-1",
      emailConnected: true,
      grantedPermissions: ["SEND_EMAIL", "READ_EMAIL", "CREATE_DRAFT"],
    });

    await markActionCompleted(executing.id, "user-1");

    auditCount = (
      sqlite.prepare("SELECT COUNT(*) AS c FROM action_audit_log").get() as {
        c: number;
      }
    ).c;
    expect(auditCount).toBeGreaterThanOrEqual(3);

    const events = sqlite
      .prepare(
        "SELECT metadata_json FROM action_audit_log ORDER BY created_at ASC"
      )
      .all() as Array<{ metadata_json: string }>;
    const parsedEvents = events.map((row) =>
      JSON.parse(row.metadata_json) as { event?: string }
    );
    expect(parsedEvents.some((e) => e.event === "action_created")).toBe(true);
    expect(parsedEvents.some((e) => e.event === "action_confirmed")).toBe(true);
    expect(parsedEvents.some((e) => e.event === "action_completed")).toBe(true);
  });
});
