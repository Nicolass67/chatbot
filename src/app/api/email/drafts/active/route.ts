export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import {
  getOpenEmailDraftForConversation,
  toEmailDraftPreview,
} from "@/lib/email/draft";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { apiErrorResponse } from "@/lib/http/api-error";

/**
 * GET /api/email/drafts/active?conversationId=…
 * Dernier brouillon ouvert de la conversation (carte iOS après relance).
 */
export const GET = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isEmailFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
  }

  const conversationId = new URL(request.url).searchParams
    .get("conversationId")
    ?.trim();
  if (!conversationId) {
    return apiErrorResponse("VALIDATION_ERROR", "conversationId requis");
  }

  const userId = auth.userId ?? "local";
  const draft = await getOpenEmailDraftForConversation(conversationId, userId);
  if (!draft) {
    return Response.json({ draft: null });
  }

  return Response.json({ draft: await toEmailDraftPreview(draft) });
});
