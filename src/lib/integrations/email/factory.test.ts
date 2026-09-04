import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import Database from "better-sqlite3";
import { drizzle, type BetterSQLite3Database } from "drizzle-orm/better-sqlite3";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as schema from "@/lib/db/schema";
import { getEmailProvider, isEmailProviderConnected } from "./factory";
import { EmailNotConnectedError } from "./types";

const TEST_KEY = Buffer.alloc(32, 5).toString("base64");

vi.mock("@/lib/integrations/oauth/config", () => ({
  isGoogleOAuthConfigured: () => true,
  requireGoogleOAuthConfig: () => ({
    clientId: "test-client",
    clientSecret: "test-secret",
    redirectUri: "http://localhost:3000/api/oauth/gmail/callback",
    encryptionKey: TEST_KEY,
    scopes: [
      "https://www.googleapis.com/auth/gmail.readonly",
      "https://www.googleapis.com/auth/gmail.compose",
    ],
  }),
}));

vi.mock("@/lib/integrations/email/gmail/oauth", () => ({
  refreshGmailAccessToken: vi.fn(),
}));

vi.mock("@/lib/integrations/email/gmail/client", () => ({
  createGmailApiClient: vi.fn(),
}));

type TestDb = BetterSQLite3Database<typeof schema>;

let sqlite: Database.Database;
let dbPath: string;
let testDb: TestDb;

function setupSchema(db: Database.Database) {
  db.exec(`
    CREATE TABLE oauth_accounts (
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
    CREATE UNIQUE INDEX oauth_accounts_user_provider_idx
      ON oauth_accounts (user_id, provider);
  `);
}

vi.mock("@/lib/db", () => ({
  getDb: () => testDb,
}));

describe("email factory", () => {
  beforeEach(() => {
    dbPath = path.join(
      os.tmpdir(),
      `chatbot-email-factory-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
    );
    sqlite = new Database(dbPath);
    setupSchema(sqlite);
    testDb = drizzle(sqlite, { schema });
  });

  afterEach(() => {
    sqlite.close();
    if (fs.existsSync(dbPath)) fs.unlinkSync(dbPath);
  });

  it("isEmailProviderConnected false sans compte", async () => {
    expect(await isEmailProviderConnected("user-x")).toBe(false);
  });

  it("getEmailProvider lève EMAIL_NOT_CONNECTED sans OAuth", async () => {
    await expect(getEmailProvider("user-x")).rejects.toBeInstanceOf(
      EmailNotConnectedError
    );
  });

  it("getEmailProvider retourne GmailProvider avec compte connecté", async () => {
    const { upsertOAuthAccount } = await import(
      "@/lib/integrations/oauth/token-store"
    );

    await upsertOAuthAccount({
      userId: "user-1",
      provider: "gmail",
      accountEmail: "me@gmail.com",
      tokens: {
        accessToken: "plain-access",
        refreshToken: "plain-refresh",
        expiresAt: new Date(Date.now() + 3600_000).toISOString(),
        scopes: [
          "https://www.googleapis.com/auth/gmail.readonly",
          "https://www.googleapis.com/auth/gmail.compose",
        ],
      },
    });

    const provider = await getEmailProvider("user-1");
    expect(provider.accountEmail).toBe("me@gmail.com");
    expect(provider.capabilities.provider).toBe("gmail");

    const row = sqlite
      .prepare("SELECT encrypted_access_token FROM oauth_accounts WHERE user_id = ?")
      .get("user-1") as { encrypted_access_token: string };
    expect(row.encrypted_access_token).not.toBe("plain-access");
    expect(await isEmailProviderConnected("user-1")).toBe(true);
  });
});
