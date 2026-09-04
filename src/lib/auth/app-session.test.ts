import { createHash } from "node:crypto";
import { describe, expect, it, beforeEach } from "vitest";
import { getDb } from "@/lib/db";
import { appSessions } from "@/lib/db/schema";
import {
  createAppSession,
  looksLikeAppSessionToken,
  resolveAppSessionToken,
  revokeAppSessionByToken,
  isAllowedNativeRedirectUri,
} from "./app-session";

describe("app-session", () => {
  beforeEach(async () => {
    const db = getDb();
    await db.delete(appSessions);
  });

  it("looksLikeAppSessionToken", () => {
    expect(looksLikeAppSessionToken("chs_abc")).toBe(true);
    expect(looksLikeAppSessionToken("health-token")).toBe(false);
  });

  it("create + resolve + revoke", async () => {
    const created = await createAppSession({ userId: "user-a", client: "ios" });
    expect(created.accessToken.startsWith("chs_")).toBe(true);
    const resolved = await resolveAppSessionToken(created.accessToken);
    expect(resolved?.userId).toBe("user-a");

    const hash = createHash("sha256")
      .update(created.accessToken)
      .digest("hex");
    const row = await getDb().query.appSessions.findFirst({
      where: (t, { eq }) => eq(t.tokenHash, hash),
    });
    expect(row?.tokenHash).toBe(hash);

    expect(await revokeAppSessionByToken(created.accessToken)).toBe(true);
    expect(await resolveAppSessionToken(created.accessToken)).toBeNull();
  });

  it("isAllowedNativeRedirectUri", () => {
    expect(isAllowedNativeRedirectUri("chatbot-native://auth")).toBe(true);
    expect(isAllowedNativeRedirectUri("https://evil.com")).toBe(false);
  });
});
