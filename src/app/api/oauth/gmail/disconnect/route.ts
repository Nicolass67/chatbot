export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { revokeGmailToken } from "@/lib/integrations/email/gmail/oauth";
import {
  deleteOAuthAccount,
  getDecryptedAccessToken,
  getDecryptedRefreshToken,
  getOAuthAccount,
  OAuthConfigError,
  requireGoogleOAuthConfig,
} from "@/lib/integrations/oauth";

export const POST = withAuth(apiAuthGuard, async (_request, auth) => {
  try {
    requireGoogleOAuthConfig();
    const userId = auth.userId ?? "local";
    const account = await getOAuthAccount(userId, "gmail");

    if (!account) {
      return Response.json({ disconnected: true, connected: false });
    }

    try {
      const accessToken = await getDecryptedAccessToken(account);
      await revokeGmailToken(accessToken);
    } catch {
      const refreshToken = await getDecryptedRefreshToken(account);
      if (refreshToken) {
        try {
          await revokeGmailToken(refreshToken);
        } catch {
          // Révocation best-effort — on supprime quand même localement
        }
      }
    }

    await deleteOAuthAccount(userId, "gmail");

    return Response.json({ disconnected: true, connected: false });
  } catch (error) {
    if (error instanceof OAuthConfigError) {
      return Response.json({ error: error.message }, { status: 503 });
    }
    return Response.json(
      {
        error:
          error instanceof Error
            ? error.message
            : "Impossible de déconnecter Gmail.",
      },
      { status: 500 }
    );
  }
});
