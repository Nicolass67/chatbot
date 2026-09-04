export const runtime = "nodejs";

import { z } from "zod";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import {
  listMailMessagesPage,
  toPublicMessageSummary,
} from "@/lib/mail/service";
import { resolveCategoryParams, parseMailCategory } from "@/lib/mail/categories";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { EmailNotConnectedError } from "@/lib/integrations/email/types";
import { apiErrorResponse } from "@/lib/http/api-error";

const querySchema = z.object({
  q: z.string().optional(),
  label: z.string().optional(),
  category: z.string().optional(),
  maxResults: z.coerce.number().min(1).max(50).optional(),
  pageToken: z.string().optional(),
});

export const GET = withAuth(apiAuthGuard, async (request, auth) => {
  const t0 = performance.now();
  if (!isEmailFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
  }

  const userId = auth.userId ?? "local";
  const url = new URL(request.url);
  const params = querySchema.parse({
    q: url.searchParams.get("q") ?? undefined,
    label: url.searchParams.get("label") ?? undefined,
    category: url.searchParams.get("category") ?? undefined,
    maxResults: url.searchParams.get("maxResults") ?? undefined,
    pageToken: url.searchParams.get("pageToken") ?? undefined,
  });

  const category = params.category
    ? parseMailCategory(params.category)
    : undefined;
  const categoryParams = category ? resolveCategoryParams(category) : null;

  try {
    const gmailStart = performance.now();
    const page = await listMailMessagesPage({
      userId,
      query: params.q,
      label: params.label ?? categoryParams?.label,
      categoryQuery: categoryParams?.query,
      maxResults: params.maxResults ?? 50,
      pageToken: params.pageToken,
    });
    const gmailMs = performance.now() - gmailStart;
    const totalMs = performance.now() - t0;
    return Response.json(
      {
        messages: page.messages.map(toPublicMessageSummary),
        nextPageToken: page.nextPageToken,
        resultSizeEstimate: page.resultSizeEstimate,
      },
      {
        headers: {
          "Server-Timing": `gmail;dur=${gmailMs.toFixed(1)}, total;dur=${totalMs.toFixed(1)}`,
          "x-perf-gmail-ms": gmailMs.toFixed(1),
          "x-perf-api-ms": totalMs.toFixed(1),
        },
      }
    );
  } catch (error) {
    if (error instanceof EmailNotConnectedError) {
      return apiErrorResponse("EMAIL_NOT_CONNECTED", error.message);
    }
    const message =
      error instanceof Error ? error.message : "Erreur Gmail inattendue";
    console.error("[mail/messages]", message);
    return apiErrorResponse(
      "PROVIDER_ERROR",
      `Impossible de charger les mails : ${message}`
    );
  }
});
