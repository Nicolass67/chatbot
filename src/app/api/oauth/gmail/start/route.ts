export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { buildGmailAuthorizationUrl } from "@/lib/integrations/email/gmail/oauth";
import {
  createOAuthState,
  OAuthConfigError,
  requireGoogleOAuthConfig,
} from "@/lib/integrations/oauth";

export const GET = withAuth(apiAuthGuard, async (request, auth) => {
  try {
    requireGoogleOAuthConfig();
    const userId = auth.userId ?? "local";
    const state = createOAuthState(userId, "gmail");
    const authorizationUrl = buildGmailAuthorizationUrl(state);
    const url = new URL(request.url);
    const wantsJson =
      url.searchParams.get("format") === "json" ||
      (request.headers.get("accept") ?? "").includes("application/json");
    if (wantsJson) {
      return Response.json({ authorizationUrl });
    }
    return Response.redirect(authorizationUrl);
  } catch (error) {
    if (error instanceof OAuthConfigError) {
      return Response.json({ error: error.message }, { status: 503 });
    }
    return Response.json(
      {
        error:
          error instanceof Error
            ? error.message
            : "Impossible de démarrer la connexion Gmail.",
      },
      { status: 500 }
    );
  }
});
