import { createHash, randomBytes } from "node:crypto";
import { and, eq, gt, isNull } from "drizzle-orm";
import { nanoid } from "nanoid";
import { getDb } from "@/lib/db";
import { appSessions } from "@/lib/db/schema";

const APP_TOKEN_PREFIX = "chs_";
const DEFAULT_TTL_MS = 7 * 24 * 60 * 60 * 1000;

export type CreatedAppSession = {
  accessToken: string;
  expiresAt: string;
  tokenType: "Bearer";
  userId: string;
  sessionId: string;
};

function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function mintRawToken(): string {
  return `${APP_TOKEN_PREFIX}${randomBytes(32).toString("base64url")}`;
}

export function extractBearerToken(request: Request): string | null {
  const auth = request.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  const token = auth.slice("Bearer ".length).trim();
  return token || null;
}

/** True si le Bearer ressemble à une session app (pas HEALTH_CHECK_TOKEN). */
export function looksLikeAppSessionToken(token: string): boolean {
  return token.startsWith(APP_TOKEN_PREFIX);
}

export async function createAppSession(input: {
  userId: string;
  client?: string;
  userAgent?: string;
  ttlMs?: number;
}): Promise<CreatedAppSession> {
  const db = getDb();
  const accessToken = mintRawToken();
  const tokenHash = hashToken(accessToken);
  const sessionId = nanoid();
  const expiresAt = new Date(
    Date.now() + (input.ttlMs ?? DEFAULT_TTL_MS)
  ).toISOString();

  await db.insert(appSessions).values({
    id: sessionId,
    userId: input.userId,
    tokenHash,
    expiresAt,
    userAgent: input.userAgent?.slice(0, 500) ?? null,
    client: input.client?.slice(0, 64) ?? null,
  });

  return {
    accessToken,
    expiresAt,
    tokenType: "Bearer",
    userId: input.userId,
    sessionId,
  };
}

export async function resolveAppSessionToken(
  token: string
): Promise<{ userId: string; sessionId: string } | null> {
  if (!looksLikeAppSessionToken(token)) return null;
  const db = getDb();
  const tokenHash = hashToken(token);
  const now = new Date().toISOString();
  const row = await db.query.appSessions.findFirst({
    where: and(
      eq(appSessions.tokenHash, tokenHash),
      isNull(appSessions.revokedAt),
      gt(appSessions.expiresAt, now)
    ),
  });
  if (!row) return null;
  return { userId: row.userId, sessionId: row.id };
}

export async function revokeAppSessionByToken(token: string): Promise<boolean> {
  if (!looksLikeAppSessionToken(token)) return false;
  const db = getDb();
  const tokenHash = hashToken(token);
  const row = await db.query.appSessions.findFirst({
    where: eq(appSessions.tokenHash, tokenHash),
  });
  if (!row || row.revokedAt) return false;
  await db
    .update(appSessions)
    .set({ revokedAt: new Date().toISOString() })
    .where(eq(appSessions.id, row.id));
  return true;
}

export async function revokeAllAppSessionsForUser(userId: string): Promise<number> {
  const db = getDb();
  const now = new Date().toISOString();
  const active = await db.query.appSessions.findMany({
    where: and(eq(appSessions.userId, userId), isNull(appSessions.revokedAt)),
  });
  for (const row of active) {
    await db
      .update(appSessions)
      .set({ revokedAt: now })
      .where(eq(appSessions.id, row.id));
  }
  return active.length;
}

const ALLOWED_NATIVE_REDIRECTS = new Set([
  "chatbot-native://auth",
  "fr.nicolazer.chatbot.native://auth",
]);

export function isAllowedNativeRedirectUri(uri: string): boolean {
  const trimmed = uri.trim();
  if (ALLOWED_NATIVE_REDIRECTS.has(trimmed)) return true;
  // Allow query-less exact match only
  try {
    const u = new URL(trimmed);
    const base = `${u.protocol}//${u.host}${u.pathname}`.replace(/\/$/, "");
    return ALLOWED_NATIVE_REDIRECTS.has(base) || ALLOWED_NATIVE_REDIRECTS.has(trimmed);
  } catch {
    return false;
  }
}
