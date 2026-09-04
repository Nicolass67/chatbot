export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import {
  isGoogleOAuthConfigured,
  listOAuthAccountsPublic,
  requireGoogleOAuthConfig,
} from "@/lib/integrations/oauth";

export const GET = withAuth(apiAuthGuard, async (_request, auth) => {
  const userId = auth.userId ?? "local";

  if (!isGoogleOAuthConfigured()) {
    return Response.json({
      configured: false,
      accounts: [],
      redirectUri: null,
    });
  }

  const accounts = await listOAuthAccountsPublic(userId);
  const { redirectUri } = requireGoogleOAuthConfig();

  return Response.json({
    configured: true,
    accounts,
    redirectUri,
  });
});
