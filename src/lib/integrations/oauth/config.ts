import { getEnv } from "@/lib/config/env";
import { GMAIL_OAUTH_SCOPES } from "@/lib/policy/scopes";

export class OAuthConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OAuthConfigError";
  }
}

export interface GoogleOAuthConfig {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
  encryptionKey: string;
  scopes: readonly string[];
}

export function isEmailFeatureEnabled(): boolean {
  return getEnv().EMAIL_ENABLED === true;
}

export function isGoogleOAuthConfigured(): boolean {
  const env = getEnv();
  return Boolean(
    env.GOOGLE_OAUTH_CLIENT_ID &&
      env.GOOGLE_OAUTH_CLIENT_SECRET &&
      env.GOOGLE_OAUTH_REDIRECT_URI &&
      env.OAUTH_TOKEN_ENCRYPTION_KEY
  );
}

export function requireGoogleOAuthConfig(): GoogleOAuthConfig {
  if (!isEmailFeatureEnabled()) {
    throw new OAuthConfigError(
      "La fonctionnalité email est désactivée (EMAIL_ENABLED=false)."
    );
  }

  const env = getEnv();
  const clientId = env.GOOGLE_OAUTH_CLIENT_ID?.trim();
  const clientSecret = env.GOOGLE_OAUTH_CLIENT_SECRET?.trim();
  const redirectUri = env.GOOGLE_OAUTH_REDIRECT_URI?.trim();
  const encryptionKey = env.OAUTH_TOKEN_ENCRYPTION_KEY?.trim();

  if (!clientId || !clientSecret || !redirectUri || !encryptionKey) {
    throw new OAuthConfigError(
      "Configuration OAuth Gmail incomplète. Vérifiez GOOGLE_OAUTH_* et OAUTH_TOKEN_ENCRYPTION_KEY."
    );
  }

  return {
    clientId,
    clientSecret,
    redirectUri,
    encryptionKey,
    scopes: GMAIL_OAUTH_SCOPES,
  };
}
