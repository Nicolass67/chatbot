import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import Database from "better-sqlite3";
import { drizzle, type BetterSQLite3Database } from "drizzle-orm/better-sqlite3";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as schema from "@/lib/db/schema";
import {
  deleteOAuthAccount,
  getOAuthAccount,
  getValidOAuthTokens,
  upsertOAuthAccount,
} from "./token-store";

const TEST_KEY = Buffer.alloc(32, 3).toString("base64");

vi.mock("./config", () => ({
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

describe("oauth token store", () => {
  beforeEach(() => {
    dbPath = path.join(
      os.tmpdir(),
      `chatbot-oauth-${Date.now()}-${Math.random().toString(36).slice(2)}.db`
    );
    sqlite = new Database(dbPath);
    setupSchema(sqlite);
    testDb = drizzle(sqlite, { schema });
  });

  afterEach(() => {
    sqlite.close();
    if (fs.existsSync(dbPath)) fs.unlinkSync(dbPath);
  });

  it("upsert chiffre les tokens (pas en clair en DB)", async () => {
    await upsertOAuthAccount({
      userId: "user-1",
      provider: "gmail",
      accountEmail: "me@gmail.com",
      tokens: {
        accessToken: "access-plain",
        refreshToken: "refresh-plain",
        expiresAt: new Date(Date.now() + 3600_000).toISOString(),
        scopes: ["https://www.googleapis.com/auth/gmail.readonly"],
      },
    });

    const row = sqlite
      .prepare(`SELECT encrypted_access_token FROM oauth_accounts WHERE user_id = ?`)
      .get("user-1") as { encrypted_access_token: string };

    expect(row.encrypted_access_token).not.toContain("access-plain");
  });

  it("refresh concurrent partage une seule promesse", async () => {
    const expired = new Date(Date.now() - 60_000).toISOString();
    await upsertOAuthAccount({
      userId: "user-1",
      provider: "gmail",
      accountEmail: "me@gmail.com",
      tokens: {
        accessToken: "old-access",
        refreshToken: "refresh-1",
        expiresAt: expired,
        scopes: [
          "https://www.googleapis.com/auth/gmail.readonly",
          "https://www.googleapis.com/auth/gmail.compose",
        ],
      },
    });

    let refreshCalls = 0;
    const refreshFn = vi.fn(async () => {
      refreshCalls += 1;
      await new Promise((r) => setTimeout(r, 50));
      return {
        accessToken: "new-access",
        refreshToken: "refresh-1",
        expiresAt: new Date(Date.now() + 3600_000).toISOString(),
        scopes: [
          "https://www.googleapis.com/auth/gmail.readonly",
          "https://www.googleapis.com/auth/gmail.compose",
        ],
      };
    });

    const [a, b] = await Promise.all([
      getValidOAuthTokens("user-1", "gmail", refreshFn),
      getValidOAuthTokens("user-1", "gmail", refreshFn),
    ]);

    expect(a.accessToken).toBe("new-access");
    expect(b.accessToken).toBe("new-access");
    expect(refreshCalls).toBe(1);
    expect(refreshFn).toHaveBeenCalledTimes(1);
  });

  it("supprime un compte OAuth", async () => {
    await upsertOAuthAccount({
      userId: "user-1",
      provider: "gmail",
      accountEmail: "me@gmail.com",
      tokens: {
        accessToken: "access",
        refreshToken: "refresh",
        expiresAt: new Date(Date.now() + 3600_000).toISOString(),
        scopes: [],
      },
    });

    expect(await deleteOAuthAccount("user-1", "gmail")).toBe(true);
    expect(await getOAuthAccount("user-1", "gmail")).toBeNull();
  });
});
