import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import Database from "better-sqlite3";
import { drizzle, type BetterSQLite3Database } from "drizzle-orm/better-sqlite3";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as schema from "@/lib/db/schema";
import { emailCreateDraftTool } from "./create-draft";
import { emailListTool } from "./list";
import { emailSearchTool } from "./search";
import type { ToolContext } from "@/lib/tools/types";

const mockListMessages = vi.fn();
const mockSearch = vi.fn();
const mockCreateDraft = vi.fn();

vi.mock("@/lib/integrations/email", () => ({
  getEmailProvider: vi.fn(async () => ({
    accountEmail: "me@gmail.com",
    capabilities: { provider: "gmail" },
    listMessages: mockListMessages,
    search: mockSearch,
    createDraft: mockCreateDraft,
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
  `);
}

vi.mock("@/lib/db", () => ({
  getDb: () => testDb,
}));

const baseCtx: ToolContext = {
  signal: AbortSignal.timeout(5000),
  settings: {} as import("@/lib/settings/service").AppSettings,
  conversationId: "conv-1",
  runtimeLocation: "local",
  userId: "user-1",
};

describe("email tools", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    dbPath = path.join(
      os.tmpdir(),
      `chatbot-email-tools-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
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

  it("email_list retourne des messages marqués untrusted", async () => {
    mockListMessages.mockResolvedValueOnce([
      {
        id: "m1",
        threadId: "t1",
        from: { email: "a@example.com" },
        to: [],
        cc: [],
        bcc: [],
        subject: "Hello",
        date: "2025-09-01",
        snippet: "Hi",
        bodyText: "Contenu",
        labelIds: ["INBOX"],
        hasAttachments: false,
        attachments: [],
        isUnread: false,
      },
    ]);

    const result = await emailListTool.execute({}, baseCtx);
    expect(result).toMatchObject({
      untrusted: true,
      count: 1,
      accountEmail: "me@gmail.com",
    });
  });

  it("email_search délègue au provider", async () => {
    mockSearch.mockResolvedValueOnce([]);

    await emailSearchTool.execute({ query: "is:unread" }, baseCtx);

    expect(mockSearch).toHaveBeenCalledWith({
      query: "is:unread",
      maxResults: 20,
    });
  });

  it("email_create_draft persiste en DB", async () => {
    mockCreateDraft.mockResolvedValueOnce({
      providerDraftId: "gmail-draft-1",
      threadId: "thread-1",
      to: ["dest@example.com"],
      cc: [],
      bcc: [],
      subject: "Test",
      bodyText: "Corps",
    });

    const result = await emailCreateDraftTool.execute(
      {
        to: "dest@example.com",
        subject: "Test",
        bodyText: "Corps",
        threadId: "thread-1",
      },
      baseCtx
    );

    expect(result).toMatchObject({
      draftId: expect.any(String),
      providerDraftId: "gmail-draft-1",
      status: "draft",
      requiresConfirmation: true,
    });

    const row = sqlite
      .prepare("SELECT provider_draft_id, status FROM email_drafts WHERE id = ?")
      .get((result as { draftId: string }).draftId) as {
      provider_draft_id: string;
      status: string;
    };
    expect(row.provider_draft_id).toBe("gmail-draft-1");
    expect(row.status).toBe("draft");
  });
});
