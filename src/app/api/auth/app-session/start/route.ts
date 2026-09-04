export const runtime = "nodejs";

import {
  createAppSession,
  isAllowedNativeRedirectUri,
} from "@/lib/auth/app-session";
import { apiErrorResponse } from "@/lib/http/api-error";

/**
 * Démarre une session app après Access (ASWebAuthenticationSession).
 * Le middleware a déjà validé Access (ou user local en dev) et injecté x-user-id.
 *
 * GET ?redirect_uri=chatbot-native://auth
 * → 302 redirect_uri?token=…&expiresAt=…
 */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const redirectUri =
    url.searchParams.get("redirect_uri")?.trim() || "chatbot-native://auth";

  if (!isAllowedNativeRedirectUri(redirectUri)) {
    return apiErrorResponse("VALIDATION_ERROR", "redirect_uri non autorisé");
  }

  const userId = request.headers.get("x-user-id")?.trim();
  if (!userId) {
    return apiErrorResponse(
      "AUTH_REQUIRED",
      "Cloudflare Access requis pour créer une session app"
    );
  }

  const session = await createAppSession({
    userId,
    client: request.headers.get("x-client")?.trim() || "ios",
    userAgent: request.headers.get("user-agent") ?? undefined,
  });

  const dest = new URL(redirectUri);
  dest.searchParams.set("token", session.accessToken);
  dest.searchParams.set("expiresAt", session.expiresAt);
  dest.searchParams.set("tokenType", session.tokenType);
  dest.searchParams.set("userId", session.userId);

  return Response.redirect(dest.toString(), 302);
}
