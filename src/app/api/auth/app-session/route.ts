export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import {
  createAppSession,
  extractBearerToken,
  revokeAppSessionByToken,
  revokeAllAppSessionsForUser,
} from "@/lib/auth/app-session";
import { apiErrorResponse } from "@/lib/http/api-error";

/** POST — crée une session Bearer (appelant déjà authentifié Access / middleware). */
export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  const userId = auth.userId ?? "local";
  const session = await createAppSession({
    userId,
    client: request.headers.get("x-client")?.trim() || "ios",
    userAgent: request.headers.get("user-agent") ?? undefined,
  });

  return Response.json({
    accessToken: session.accessToken,
    expiresAt: session.expiresAt,
    tokenType: session.tokenType,
    userId: session.userId,
  });
});

/** DELETE — révoque la session courante (Bearer) ou toutes les sessions user. */
export const DELETE = withAuth(apiAuthGuard, async (request, auth) => {
  const url = new URL(request.url);
  const all = url.searchParams.get("all") === "1";
  if (all) {
    const n = await revokeAllAppSessionsForUser(auth.userId ?? "local");
    return Response.json({ revoked: n });
  }
  const token = extractBearerToken(request);
  if (!token) {
    return apiErrorResponse("VALIDATION_ERROR", "Bearer requis pour révoquer");
  }
  const ok = await revokeAppSessionByToken(token);
  if (!ok) {
    return apiErrorResponse("NOT_FOUND", "Session introuvable");
  }
  return Response.json({ revoked: 1 });
});
