import fs from "node:fs";
import path from "node:path";
import Database from "better-sqlite3";
import { drizzle, type BetterSQLite3Database } from "drizzle-orm/better-sqlite3";
import { getEnv } from "@/lib/config/env";
import { instrumentSqliteDatabase } from "@/lib/perf/audit";
import * as schema from "./schema";

export type AppDatabase = BetterSQLite3Database<typeof schema>;

declare global {
  var __db: AppDatabase | undefined;
  var __sqlite: Database.Database | undefined;
}

function resolveDbPath(): string {
  const envPath = getEnv().DATABASE_URL;
  if (path.isAbsolute(envPath)) return envPath;
  return path.join(process.cwd(), envPath);
}

function initFts5(sqlite: Database.Database) {
  sqlite.exec(`
    CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
      content,
      category,
      content='memories',
      content_rowid='rowid'
    );
  `);

  sqlite.exec(`
    CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
      INSERT INTO memories_fts(rowid, content, category) VALUES (new.rowid, new.content, new.category);
    END;
  `);

  sqlite.exec(`
    CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
      INSERT INTO memories_fts(memories_fts, rowid, content, category) VALUES('delete', old.rowid, old.content, old.category);
    END;
  `);

  sqlite.exec(`
    CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
      INSERT INTO memories_fts(memories_fts, rowid, content, category) VALUES('delete', old.rowid, old.content, old.category);
      INSERT INTO memories_fts(rowid, content, category) VALUES (new.rowid, new.content, new.category);
    END;
  `);

  sqlite.exec(`
    CREATE VIRTUAL TABLE IF NOT EXISTS document_chunks_fts USING fts5(
      content,
      attachment_id UNINDEXED,
      conversation_id UNINDEXED,
      content='document_chunks',
      content_rowid='rowid'
    );
  `);

  sqlite.exec(`
    CREATE TRIGGER IF NOT EXISTS document_chunks_ai AFTER INSERT ON document_chunks BEGIN
      INSERT INTO document_chunks_fts(rowid, content, attachment_id, conversation_id)
      VALUES (new.rowid, new.content, new.attachment_id, new.conversation_id);
    END;
  `);

  sqlite.exec(`
    CREATE TRIGGER IF NOT EXISTS document_chunks_ad AFTER DELETE ON document_chunks BEGIN
      INSERT INTO document_chunks_fts(document_chunks_fts, rowid, content, attachment_id, conversation_id)
      VALUES('delete', old.rowid, old.content, old.attachment_id, old.conversation_id);
    END;
  `);

  sqlite.exec(`
    CREATE TRIGGER IF NOT EXISTS document_chunks_au AFTER UPDATE ON document_chunks BEGIN
      INSERT INTO document_chunks_fts(document_chunks_fts, rowid, content, attachment_id, conversation_id)
      VALUES('delete', old.rowid, old.content, old.attachment_id, old.conversation_id);
      INSERT INTO document_chunks_fts(rowid, content, attachment_id, conversation_id)
      VALUES (new.rowid, new.content, new.attachment_id, new.conversation_id);
    END;
  `);

  sqlite.exec(`
    CREATE VIRTUAL TABLE IF NOT EXISTS file_index_chunks_fts USING fts5(
      content,
      entry_id UNINDEXED,
      user_id UNINDEXED,
      root_id UNINDEXED,
      content='file_index_chunks',
      content_rowid='rowid'
    );
  `);

  sqlite.exec(`
    CREATE TRIGGER IF NOT EXISTS file_index_chunks_ai AFTER INSERT ON file_index_chunks BEGIN
      INSERT INTO file_index_chunks_fts(rowid, content, entry_id, user_id, root_id)
      VALUES (new.rowid, new.content, new.entry_id, new.user_id, new.root_id);
    END;
  `);

  sqlite.exec(`
    CREATE TRIGGER IF NOT EXISTS file_index_chunks_ad AFTER DELETE ON file_index_chunks BEGIN
      INSERT INTO file_index_chunks_fts(file_index_chunks_fts, rowid, content, entry_id, user_id, root_id)
      VALUES('delete', old.rowid, old.content, old.entry_id, old.user_id, old.root_id);
    END;
  `);

  sqlite.exec(`
    CREATE TRIGGER IF NOT EXISTS file_index_chunks_au AFTER UPDATE ON file_index_chunks BEGIN
      INSERT INTO file_index_chunks_fts(file_index_chunks_fts, rowid, content, entry_id, user_id, root_id)
      VALUES('delete', old.rowid, old.content, old.entry_id, old.user_id, old.root_id);
      INSERT INTO file_index_chunks_fts(rowid, content, entry_id, user_id, root_id)
      VALUES (new.rowid, new.content, new.entry_id, new.user_id, new.root_id);
    END;
  `);
}

function migrateSchema(sqlite: Database.Database) {
  const attachmentCols = sqlite
    .prepare(`PRAGMA table_info(attachments)`)
    .all() as Array<{ name: string }>;
  const colNames = new Set(attachmentCols.map((c) => c.name));

  if (attachmentCols.length > 0 && !colNames.has("conversation_id")) {
    sqlite.exec(`
      CREATE TABLE attachments_new (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
        message_id TEXT REFERENCES messages(id) ON DELETE CASCADE,
        type TEXT NOT NULL,
        filename TEXT NOT NULL,
        mime_type TEXT NOT NULL,
        local_path TEXT NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        extracted_char_count INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (datetime('now'))
      );
      INSERT INTO attachments_new (id, conversation_id, message_id, type, filename, mime_type, local_path, size_bytes, status, extracted_char_count, created_at)
      SELECT a.id, m.conversation_id, a.message_id,
        CASE WHEN a.type = 'image' THEN 'image' ELSE 'document' END,
        a.filename, a.mime_type, a.local_path, a.size_bytes, 'attached', 0, a.created_at
      FROM attachments a
      JOIN messages m ON m.id = a.message_id;
      DROP TABLE attachments;
      ALTER TABLE attachments_new RENAME TO attachments;
    `);
  } else if (attachmentCols.length > 0) {
    if (!colNames.has("status")) {
      sqlite.exec(
        `ALTER TABLE attachments ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'`
      );
    }
    if (!colNames.has("extracted_char_count")) {
      sqlite.exec(
        `ALTER TABLE attachments ADD COLUMN extracted_char_count INTEGER NOT NULL DEFAULT 0`
      );
    }
  }

  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS document_chunks (
      id TEXT PRIMARY KEY,
      attachment_id TEXT NOT NULL REFERENCES attachments(id) ON DELETE CASCADE,
      conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      chunk_index INTEGER NOT NULL,
      content TEXT NOT NULL,
      token_estimate INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);

  const convCols = sqlite
    .prepare(`PRAGMA table_info(conversations)`)
    .all() as Array<{ name: string }>;
  const convColNames = new Set(convCols.map((c) => c.name));
  if (convCols.length > 0 && !convColNames.has("reasoning_effort")) {
    sqlite.exec(`ALTER TABLE conversations ADD COLUMN reasoning_effort TEXT`);
  }
  if (convCols.length > 0 && !convColNames.has("chat_mode")) {
    sqlite.exec(
      `ALTER TABLE conversations ADD COLUMN chat_mode TEXT NOT NULL DEFAULT 'chat'`
    );
  }
  if (convCols.length > 0 && !convColNames.has("agent_depth")) {
    sqlite.exec(
      `ALTER TABLE conversations ADD COLUMN agent_depth TEXT NOT NULL DEFAULT 'standard'`
    );
  }
  if (convCols.length > 0 && !convColNames.has("scope")) {
    sqlite.exec(
      `ALTER TABLE conversations ADD COLUMN scope TEXT NOT NULL DEFAULT 'general'`
    );
  }
  if (convCols.length > 0 && !convColNames.has("context_key")) {
    sqlite.exec(`ALTER TABLE conversations ADD COLUMN context_key TEXT`);
  }
  if (convCols.length > 0 && !convColNames.has("context_label")) {
    sqlite.exec(`ALTER TABLE conversations ADD COLUMN context_label TEXT`);
  }

  const pendingCols = sqlite
    .prepare(`PRAGMA table_info(pending_actions)`)
    .all() as Array<{ name: string }>;
  const pendingColNames = new Set(pendingCols.map((c) => c.name));
  if (pendingCols.length > 0 && !pendingColNames.has("resource_id")) {
    sqlite.exec(`ALTER TABLE pending_actions ADD COLUMN resource_id TEXT`);
  }

  const emailDraftCols = sqlite
    .prepare(`PRAGMA table_info(email_drafts)`)
    .all() as Array<{ name: string }>;
  const emailDraftColNames = new Set(emailDraftCols.map((c) => c.name));
  if (
    emailDraftCols.length > 0 &&
    !emailDraftColNames.has("attachment_ids_json")
  ) {
    sqlite.exec(
      `ALTER TABLE email_drafts ADD COLUMN attachment_ids_json TEXT NOT NULL DEFAULT '[]'`
    );
  }

  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS agent_runs (
      id TEXT PRIMARY KEY,
      conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      message_id TEXT REFERENCES messages(id) ON DELETE SET NULL,
      depth TEXT NOT NULL,
      model TEXT NOT NULL,
      started_at TEXT NOT NULL,
      ended_at TEXT,
      status TEXT NOT NULL,
      steps_json TEXT NOT NULL DEFAULT '[]',
      stats_json TEXT NOT NULL DEFAULT '{}',
      limit_reason TEXT
    );
  `);

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
    CREATE TABLE IF NOT EXISTS app_sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      token_hash TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      revoked_at TEXT,
      user_agent TEXT,
      client TEXT
    );
  `);
  sqlite.exec(`
    CREATE UNIQUE INDEX IF NOT EXISTS app_sessions_token_hash_idx
    ON app_sessions (token_hash);
  `);
  sqlite.exec(`
    CREATE INDEX IF NOT EXISTS app_sessions_user_id_idx
    ON app_sessions (user_id);
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

  if (pendingCols.length > 0 && !pendingColNames.has("payload_json")) {
    sqlite.exec(`ALTER TABLE pending_actions ADD COLUMN payload_json TEXT`);
  }

  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS file_roots (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      label TEXT NOT NULL,
      absolute_path TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1,
      is_default INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);
  sqlite.exec(`
    CREATE INDEX IF NOT EXISTS file_roots_user_idx ON file_roots (user_id);
  `);
  sqlite.exec(`
    CREATE UNIQUE INDEX IF NOT EXISTS file_roots_user_path_idx
    ON file_roots (user_id, absolute_path);
  `);

  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS file_references (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      root_id TEXT NOT NULL REFERENCES file_roots(id) ON DELETE CASCADE,
      relative_path TEXT NOT NULL,
      display_name TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      mtime_ms INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      expires_at TEXT NOT NULL
    );
  `);
  sqlite.exec(`
    CREATE INDEX IF NOT EXISTS file_references_user_idx ON file_references (user_id);
  `);
  sqlite.exec(`
    CREATE INDEX IF NOT EXISTS file_references_expires_idx ON file_references (expires_at);
  `);

  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS file_index_entries (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      root_id TEXT NOT NULL REFERENCES file_roots(id) ON DELETE CASCADE,
      relative_path TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      mtime_ms INTEGER NOT NULL DEFAULT 0,
      mime TEXT NOT NULL DEFAULT 'application/octet-stream',
      content_hash TEXT,
      indexed_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);
  sqlite.exec(`
    CREATE UNIQUE INDEX IF NOT EXISTS file_index_entries_root_path_idx
    ON file_index_entries (root_id, relative_path);
  `);
  sqlite.exec(`
    CREATE INDEX IF NOT EXISTS file_index_entries_user_idx ON file_index_entries (user_id);
  `);

  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS file_index_chunks (
      id TEXT PRIMARY KEY,
      entry_id TEXT NOT NULL REFERENCES file_index_entries(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL,
      root_id TEXT NOT NULL,
      chunk_index INTEGER NOT NULL,
      content TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);
  sqlite.exec(`
    CREATE INDEX IF NOT EXISTS file_index_chunks_entry_idx ON file_index_chunks (entry_id);
  `);
  sqlite.exec(`
    CREATE INDEX IF NOT EXISTS file_index_chunks_user_idx ON file_index_chunks (user_id);
  `);
}

function createDb(): AppDatabase {
  const dbPath = resolveDbPath();
  const dir = path.dirname(dbPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  const attachmentsDir = path.join(process.cwd(), "data", "attachments");
  if (!fs.existsSync(attachmentsDir)) {
    fs.mkdirSync(attachmentsDir, { recursive: true });
  }

  const sqlite = new Database(dbPath);
  sqlite.pragma("journal_mode = WAL");
  sqlite.pragma("foreign_keys = ON");

  migrateSchema(sqlite);
  initFts5(sqlite);

  // Instrument AFTER migrations so PRAGMA/DDL noise is excluded from nav audits.
  const instrumented = instrumentSqliteDatabase(sqlite);
  global.__sqlite = instrumented;
  return drizzle(instrumented, { schema });
}

export function getDb(): AppDatabase {
  if (!global.__db) {
    global.__db = createDb();
  }
  return global.__db;
}

export function getSqlite(): Database.Database {
  if (!global.__sqlite) {
    getDb();
  }
  return global.__sqlite!;
}

export function getDatabasePath(): string {
  return resolveDbPath();
}
