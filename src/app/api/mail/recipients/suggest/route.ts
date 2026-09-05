export const runtime = "nodejs";

import { z } from "zod";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { suggestMailRecipients } from "@/lib/mail/resolve-recipient";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { apiErrorResponse } from "@/lib/http/api-error";

const querySchema = z.object({
  q: z.string().min(1).max(120),
  limit: z.coerce.number().min(1).max(20).optional(),
});

export const GET = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isEmailFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
  }

  const userId = auth.userId ?? "local";
  const url = new URL(request.url);
  const params = querySchema.parse({
    q: url.searchParams.get("q") ?? "",
    limit: url.searchParams.get("limit") ?? undefined,
  });

  const recipients = await suggestMailRecipients({
    userId,
    query: params.q,
    limit: params.limit,
  });

  return Response.json({
    recipients: recipients.map((r) => ({
      email: r.email,
      displayName: r.displayName ?? null,
      source: r.source,
    })),
  });
});
