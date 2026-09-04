import { google } from "googleapis";
import { requireGoogleOAuthConfig } from "@/lib/integrations/oauth/config";

export function createGmailApiClient(accessToken: string) {
  const config = requireGoogleOAuthConfig();
  const auth = new google.auth.OAuth2(
    config.clientId,
    config.clientSecret,
    config.redirectUri
  );
  auth.setCredentials({ access_token: accessToken });
  return google.gmail({ version: "v1", auth });
}

export type GmailApiClient = ReturnType<typeof createGmailApiClient>;
