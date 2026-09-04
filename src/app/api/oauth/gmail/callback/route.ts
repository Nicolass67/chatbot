export const runtime = "nodejs";

import { getEnv } from "@/lib/config/env";
import {
  exchangeGmailAuthorizationCode,
  fetchGmailAccountEmail,
} from "@/lib/integrations/email/gmail/oauth";
import {
  consumeOAuthState,
  OAuthConfigError,
  requireGoogleOAuthConfig,
  upsertOAuthAccount,
} from "@/lib/integrations/oauth";

function redirectToSettings(params: Record<string, string>): Response {
  const base = getEnv().PUBLIC_BASE_URL ?? "http://localhost:3000";
  const url = new URL("/settings/email", base);
  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value);
  }
  return Response.redirect(url.toString());
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const oauthError = url.searchParams.get("error");
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");

  if (oauthError) {
    return redirectToSettings({
      gmail: "error",
      reason: oauthError,
    });
  }

  if (!code || !state) {
    return redirectToSettings({
      gmail: "error",
      reason: "missing_code_or_state",
    });
  }

  const consumed = consumeOAuthState(state, "gmail");
  if (!consumed) {
    return redirectToSettings({
      gmail: "error",
      reason: "invalid_state",
    });
  }

  try {
    requireGoogleOAuthConfig();
    const tokens = await exchangeGmailAuthorizationCode(code);
    const accountEmail = await fetchGmailAccountEmail(tokens.accessToken);

    await upsertOAuthAccount({
      userId: consumed.userId,
      provider: "gmail",
      accountEmail,
      tokens,
    });

    return redirectToSettings({ gmail: "connected" });
  } catch (error) {
    const reason =
      error instanceof OAuthConfigError
        ? "config_error"
        : error instanceof Error
          ? "exchange_failed"
          : "unknown";

    return redirectToSettings({
      gmail: "error",
      reason,
    });
  }
}
