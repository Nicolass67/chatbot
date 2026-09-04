export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { getPublicPendingSendForConversation } from "@/lib/email/send";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { apiErrorResponse } from "@/lib/http/api-error";

export const GET = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isEmailFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
  }

  const conversationId = new URL(request.url).searchParams.get("conversationId");
  if (!conversationId) {
    return Response.json(
      { error: "conversationId requis" },
      { status: 400 }
    );
  }

  const userId = auth.userId ?? "local";
  const action = await getPublicPendingSendForConversation(
    conversationId,
    userId
  );

  return Response.json({ action });
});
