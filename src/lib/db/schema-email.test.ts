import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import Database from "better-sqlite3";

const EMAIL_TABLES = [
  "oauth_accounts",
  "email_drafts",
  "pending_actions",
  "action_audit_log",
] as const;

function createIsolatedDb(): { dbPath: string; sqlite: Database.Database } {
  const dbPath = path.join(
    os.tmpdir(),
    `chatbot-phase0-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
  );
  const sqlite = new Database(dbPath);
  sqlite.pragma("foreign_keys = ON");

  sqlite.exec(`
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
  `);

  return { dbPath, sqlite };
}

function runEmailMigrations(sqlite: Database.Database) {
  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS oauth_accounts (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      provider TEXT NOT NULL,
      account_email TEXT NOT NULL,
      encrypted_access_token TEXT NOT NULL,
      encrypted_refresh_token TEXT,
      expires_at TEXT,
      scopes_json TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);
  sqlite.exec(`
    CREATE UNIQUE INDEX IF NOT EXISTS oauth_accounts_user_provider_idx
    ON oauth_accounts (user_id, provider);
  `);
  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS email_drafts (
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
  `);
  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS pending_actions (
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
  `);
  sqlite.exec(`
    CREATE INDEX IF NOT EXISTS pending_actions_conversation_status_idx
    ON pending_actions (conversation_id, status);
  `);
  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS action_audit_log (
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

describe("email schema migrations (phase 0)", () => {
  let dbPath: string;
  let sqlite: Database.Database;

  beforeEach(() => {
    ({ dbPath, sqlite } = createIsolatedDb());
  });

  afterEach(() => {
    sqlite.close();
    if (fs.existsSync(dbPath)) {
      fs.unlinkSync(dbPath);
    }
  });

  it("crée les 4 tables email", () => {
    runEmailMigrations(sqlite);

    const tables = sqlite
      .prepare(
        `SELECT name FROM sqlite_master WHERE type='table' AND name IN (${EMAIL_TABLES.map(() => "?").join(", ")})`
      )
      .all(...EMAIL_TABLES) as Array<{ name: string }>;

    expect(tables.map((t) => t.name).sort()).toEqual([...EMAIL_TABLES].sort());
  });

  it("est idempotente (double migration sans erreur)", () => {
    runEmailMigrations(sqlite);
    expect(() => runEmailMigrations(sqlite)).not.toThrow();
  });

  it("enforce l'unicité oauth_accounts (user_id, provider)", () => {
    runEmailMigrations(sqlite);

    sqlite
      .prepare(
        `INSERT INTO oauth_accounts (id, user_id, provider, account_email, encrypted_access_token, scopes_json)
         VALUES (?, ?, ?, ?, ?, ?)`
      )
      .run("oa1", "local", "gmail", "a@test.com", "enc", "[]");

    expect(() =>
      sqlite
        .prepare(
          `INSERT INTO oauth_accounts (id, user_id, provider, account_email, encrypted_access_token, scopes_json)
           VALUES (?, ?, ?, ?, ?, ?)`
        )
        .run("oa2", "local", "gmail", "b@test.com", "enc2", "[]")
    ).toThrow();
  });
});
