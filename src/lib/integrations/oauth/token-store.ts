import { and, eq } from "drizzle-orm";
import { nanoid } from "nanoid";
import { getDb } from "@/lib/db";
import { oauthAccounts } from "@/lib/db/schema";
import { requireGoogleOAuthConfig } from "./config";
import { decryptSecret, encryptSecret } from "./token-crypto";
import type {
  OAuthAccountPublic,
  OAuthProvider,
  OAuthTokenPair,
  StoredOAuthAccount,
} from "./types";
import { toPublicOAuthAccount } from "./types";

const refreshInFlight = new Map<string, Promise<OAuthTokenPair>>();

const REFRESH_BUFFER_MS = 5 * 60 * 1000;

export async function getOAuthAccount(
  userId: string,
  provider: OAuthProvider = "gmail"
): Promise<StoredOAuthAccount | null> {
  const db = getDb();
  const row = await db.query.oauthAccounts.findFirst({
    where: and(
      eq(oauthAccounts.userId, userId),
      eq(oauthAccounts.provider, provider)
    ),
  });
  return row ?? null;
}

export async function listOAuthAccountsPublic(
  userId: string
): Promise<OAuthAccountPublic[]> {
  const db = getDb();
  const rows = await db.query.oauthAccounts.findMany({
    where: eq(oauthAccounts.userId, userId),
  });
  return rows.map(toPublicOAuthAccount);
}

export async function upsertOAuthAccount(params: {
  userId: string;
  provider: OAuthProvider;
  accountEmail: string;
  tokens: OAuthTokenPair;
}): Promise<StoredOAuthAccount> {
  const { encryptionKey } = requireGoogleOAuthConfig();
  const db = getDb();
  const now = new Date().toISOString();

  const encryptedAccessToken = encryptSecret(
    params.tokens.accessToken,
    encryptionKey
  );
  const encryptedRefreshToken = params.tokens.refreshToken
    ? encryptSecret(params.tokens.refreshToken, encryptionKey)
    : null;

  const existing = await getOAuthAccount(params.userId, params.provider);

  if (existing) {
    await db
      .update(oauthAccounts)
      .set({
        accountEmail: params.accountEmail,
        encryptedAccessToken,
        encryptedRefreshToken:
          encryptedRefreshToken ?? existing.encryptedRefreshToken,
        expiresAt: params.tokens.expiresAt,
        scopesJson: JSON.stringify(params.tokens.scopes),
        updatedAt: now,
      })
      .where(eq(oauthAccounts.id, existing.id));

    const updated = await getOAuthAccount(params.userId, params.provider);
    if (!updated) {
      throw new Error("Échec de mise à jour du compte OAuth.");
    }
    return updated;
  }

  const id = nanoid();
  await db.insert(oauthAccounts).values({
    id,
    userId: params.userId,
    provider: params.provider,
    accountEmail: params.accountEmail,
    encryptedAccessToken,
    encryptedRefreshToken,
    expiresAt: params.tokens.expiresAt,
    scopesJson: JSON.stringify(params.tokens.scopes),
    createdAt: now,
    updatedAt: now,
  });

  const created = await getOAuthAccount(params.userId, params.provider);
  if (!created) {
    throw new Error("Échec de création du compte OAuth.");
  }
  return created;
}

export async function deleteOAuthAccount(
  userId: string,
  provider: OAuthProvider = "gmail"
): Promise<boolean> {
  const db = getDb();
  const existing = await getOAuthAccount(userId, provider);
  if (!existing) return false;

  await db
    .delete(oauthAccounts)
    .where(
      and(
        eq(oauthAccounts.userId, userId),
        eq(oauthAccounts.provider, provider)
      )
    );
  return true;
}

function isAccessTokenExpired(expiresAt: string | null): boolean {
  if (!expiresAt) return true;
  return new Date(expiresAt).getTime() <= Date.now() + REFRESH_BUFFER_MS;
}

export async function getDecryptedAccessToken(
  account: StoredOAuthAccount
): Promise<string> {
  const { encryptionKey } = requireGoogleOAuthConfig();
  return decryptSecret(account.encryptedAccessToken, encryptionKey);
}

export async function getDecryptedRefreshToken(
  account: StoredOAuthAccount
): Promise<string | null> {
  if (!account.encryptedRefreshToken) return null;
  const { encryptionKey } = requireGoogleOAuthConfig();
  return decryptSecret(account.encryptedRefreshToken, encryptionKey);
}

export async function getValidOAuthTokens(
  userId: string,
  provider: OAuthProvider = "gmail",
  refreshFn: (refreshToken: string) => Promise<OAuthTokenPair>
): Promise<OAuthTokenPair> {
  const account = await getOAuthAccount(userId, provider);
  if (!account) {
    throw new Error("Compte OAuth introuvable.");
  }

  if (!isAccessTokenExpired(account.expiresAt)) {
    return {
      accessToken: await getDecryptedAccessToken(account),
      refreshToken: await getDecryptedRefreshToken(account),
      expiresAt: account.expiresAt,
      scopes: JSON.parse(account.scopesJson) as string[],
    };
  }

  let inFlight = refreshInFlight.get(account.id);
  if (!inFlight) {
    inFlight = (async () => {
      const refreshToken = await getDecryptedRefreshToken(account);
      if (!refreshToken) {
        throw new Error("Refresh token indisponible — reconnectez Gmail.");
      }
      const refreshed = await refreshFn(refreshToken);
      await upsertOAuthAccount({
        userId,
        provider,
        accountEmail: account.accountEmail,
        tokens: {
          accessToken: refreshed.accessToken,
          refreshToken: refreshed.refreshToken ?? refreshToken,
          expiresAt: refreshed.expiresAt,
          scopes: refreshed.scopes,
        },
      });
      return refreshed;
    })().finally(() => {
      refreshInFlight.delete(account.id);
    });
    refreshInFlight.set(account.id, inFlight);
  }

  return inFlight;
}

export function isOAuthAccountConnected(userId: string): Promise<boolean> {
  return getOAuthAccount(userId, "gmail").then((a) => a !== null);
}
