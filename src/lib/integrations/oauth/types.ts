import type { PermissionScope } from "@/lib/policy";
import { oauthScopesToGrantedPermissions } from "@/lib/policy/scopes";

export type OAuthProvider = "gmail";

export interface OAuthAccountPublic {
  id: string;
  provider: OAuthProvider;
  accountEmail: string;
  scopes: string[];
  grantedPermissions: PermissionScope[];
  expiresAt: string | null;
  connected: true;
}

export interface OAuthTokenPair {
  accessToken: string;
  refreshToken: string | null;
  expiresAt: string | null;
  scopes: string[];
}

export interface StoredOAuthAccount {
  id: string;
  userId: string;
  provider: OAuthProvider;
  accountEmail: string;
  encryptedAccessToken: string;
  encryptedRefreshToken: string | null;
  expiresAt: string | null;
  scopesJson: string;
}

export function toPublicOAuthAccount(
  account: StoredOAuthAccount
): OAuthAccountPublic {
  const scopes = JSON.parse(account.scopesJson) as string[];
  return {
    id: account.id,
    provider: account.provider,
    accountEmail: account.accountEmail,
    scopes,
    grantedPermissions: oauthScopesToGrantedPermissions(scopes),
    expiresAt: account.expiresAt,
    connected: true,
  };
}
