export const runtime = "nodejs";

import { z } from "zod";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import {
  EmailDraftError,
  getEmailDraftForUser,
  toEmailDraftPreview,
  updateEmailDraft,
} from "@/lib/email/draft";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { apiErrorResponse } from "@/lib/http/api-error";

const patchSchema = z.object({
  to: z.array(z.string().min(3)).min(1).optional(),
  cc: z.array(z.string().min(3)).optional(),
  bcc: z.array(z.string().min(3)).optional(),
  subject: z.string().min(1).max(500).optional(),
  bodyText: z.string().min(1).max(100_000).optional(),
  attachmentIds: z.array(z.string().min(1)).max(20).optional(),
});

export const GET = withAuth(
  apiAuthGuard,
  async (_request, auth, ctx: { params: Promise<{ id: string }> }) => {
    if (!isEmailFeatureEnabled()) {
      return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
    }

    const { id } = await ctx.params;
    const userId = auth.userId ?? "local";
    const draft = await getEmailDraftForUser(id, userId);

    if (!draft) {
      return apiErrorResponse("NOT_FOUND", "Brouillon introuvable");
    }

    return Response.json(await toEmailDraftPreview(draft));
  }
);

export const PATCH = withAuth(
  apiAuthGuard,
  async (request, auth, ctx: { params: Promise<{ id: string }> }) => {
    if (!isEmailFeatureEnabled()) {
      return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
    }

    const { id } = await ctx.params;
    const userId = auth.userId ?? "local";
    const body = patchSchema.parse(await request.json());

    try {
      const updated = await updateEmailDraft(id, userId, body);
      return Response.json(await toEmailDraftPreview(updated));
    } catch (error) {
      if (error instanceof EmailDraftError) {
        const status =
          error.code === "NOT_FOUND"
            ? 404
            : error.code === "VALIDATION_ERROR"
              ? 400
              : 409;
        return Response.json({ error: error.message, code: error.code }, { status });
      }
      throw error;
    }
  }
);
