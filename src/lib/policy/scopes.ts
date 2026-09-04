import type { PermissionScope } from "./types";

/** Scopes OAuth Gmail — lecture. */
export const GMAIL_SCOPE_READONLY =
  "https://www.googleapis.com/auth/gmail.readonly";
/** Scopes OAuth Gmail — brouillons et envoi. */
export const GMAIL_SCOPE_COMPOSE =
  "https://www.googleapis.com/auth/gmail.compose";
/** Scopes OAuth Gmail — modification (corbeille, labels). Re-consent requis pour comptes V1. */
export const GMAIL_SCOPE_MODIFY =
  "https://www.googleapis.com/auth/gmail.modify";

/** Scopes OAuth Gmail V1 (legacy). */
export const GMAIL_V1_OAUTH_SCOPES = [
  GMAIL_SCOPE_READONLY,
  GMAIL_SCOPE_COMPOSE,
] as const;

/** Scopes OAuth Gmail V2 — inclut gmail.modify pour la corbeille. */
export const GMAIL_OAUTH_SCOPES = [
  GMAIL_SCOPE_READONLY,
  GMAIL_SCOPE_COMPOSE,
  GMAIL_SCOPE_MODIFY,
] as const;

/** Permissions requises pour la corbeille (re-consent si absent). */
export const GMAIL_TRASH_REQUIRED_SCOPES = [
  GMAIL_SCOPE_READONLY,
  GMAIL_SCOPE_MODIFY,
] as const;

/** Mapping permission applicative email → scopes OAuth Gmail requis. */
export const PERMISSION_TO_GMAIL_SCOPES: Record<
  Extract<
    PermissionScope,
    | "READ_EMAIL"
    | "SEARCH_EMAIL"
    | "ANALYZE_EMAIL"
    | "CREATE_DRAFT"
    | "SEND_EMAIL"
    | "TRASH_EMAIL"
  >,
  readonly string[]
> = {
  READ_EMAIL: [GMAIL_SCOPE_READONLY],
  SEARCH_EMAIL: [GMAIL_SCOPE_READONLY],
  ANALYZE_EMAIL: [GMAIL_SCOPE_READONLY],
  CREATE_DRAFT: [GMAIL_SCOPE_READONLY, GMAIL_SCOPE_COMPOSE],
  SEND_EMAIL: [GMAIL_SCOPE_READONLY, GMAIL_SCOPE_COMPOSE],
  TRASH_EMAIL: [GMAIL_SCOPE_READONLY, GMAIL_SCOPE_MODIFY],
};

export function oauthScopesToGrantedPermissions(
  oauthScopes: string[]
): import("./types").PermissionScope[] {
  const granted = new Set<import("./types").PermissionScope>();
  const entries = Object.entries(PERMISSION_TO_GMAIL_SCOPES) as Array<
    [import("./types").PermissionScope, readonly string[]]
  >;
  for (const [permission, required] of entries) {
    if (required.every((scope) => oauthScopes.includes(scope))) {
      granted.add(permission);
    }
  }
  return [...granted];
}

export function hasRequiredOAuthScopes(
  oauthScopes: string[],
  required: readonly string[]
): boolean {
  return required.every((scope) => oauthScopes.includes(scope));
}
