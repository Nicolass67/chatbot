import { google } from "googleapis";
import { GMAIL_OAUTH_SCOPES } from "@/lib/policy/scopes";
import { requireGoogleOAuthConfig } from "@/lib/integrations/oauth/config";
import type { OAuthTokenPair } from "@/lib/integrations/oauth/types";

function createOAuth2Client() {
  const config = requireGoogleOAuthConfig();
  return new google.auth.OAuth2(
    config.clientId,
    config.clientSecret,
    config.redirectUri
  );
}

function tokensToPair(tokens: {
  access_token?: string | null;
  refresh_token?: string | null;
  expiry_date?: number | null;
  scope?: string | null;
}): OAuthTokenPair {
  if (!tokens.access_token) {
    throw new Error("Réponse OAuth sans access_token.");
  }

  const scopes = tokens.scope
    ? tokens.scope.split(" ").filter(Boolean)
    : [...GMAIL_OAUTH_SCOPES];

  return {
    accessToken: tokens.access_token,
    refreshToken: tokens.refresh_token ?? null,
    expiresAt:
      tokens.expiry_date != null
        ? new Date(tokens.expiry_date).toISOString()
        : null,
    scopes,
  };
}

export function buildGmailAuthorizationUrl(state: string): string {
  const config = requireGoogleOAuthConfig();
  const client = createOAuth2Client();
  return client.generateAuthUrl({
    access_type: "offline",
    prompt: "consent",
    scope: [...config.scopes],
    state,
    include_granted_scopes: true,
  });
}

export async function exchangeGmailAuthorizationCode(
  code: string
): Promise<OAuthTokenPair> {
  const client = createOAuth2Client();
  const { tokens } = await client.getToken(code);
  client.setCredentials(tokens);
  return tokensToPair(tokens);
}

export async function refreshGmailAccessToken(
  refreshToken: string
): Promise<OAuthTokenPair> {
  const client = createOAuth2Client();
  client.setCredentials({ refresh_token: refreshToken });
  const { credentials } = await client.refreshAccessToken();
  return tokensToPair({
    ...credentials,
    refresh_token: credentials.refresh_token ?? refreshToken,
  });
}

export async function revokeGmailToken(token: string): Promise<void> {
  const client = createOAuth2Client();
  await client.revokeToken(token);
}

export async function fetchGmailAccountEmail(
  accessToken: string
): Promise<string> {
  const client = createOAuth2Client();
  client.setCredentials({ access_token: accessToken });
  const gmail = google.gmail({ version: "v1", auth: client });
  const profile = await gmail.users.getProfile({ userId: "me" });
  const email = profile.data.emailAddress;
  if (!email) {
    throw new Error("Impossible de récupérer l'adresse Gmail.");
  }
  return email;
}
