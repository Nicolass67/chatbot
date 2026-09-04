export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import {
  cancelFilesMutationAction,
  confirmFilesMutationAction,
} from "@/lib/files/confirm";
import { isFilesFeatureEnabled } from "@/lib/files/feature";
import { apiErrorResponse } from "@/lib/http/api-error";

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isFilesFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Files désactivé");
  }
  const userId = auth.userId ?? "local";
  const body = (await request.json()) as {
    action?: "confirm" | "cancel";
    actionId?: string;
    confirmationToken?: string;
  };

  if (!body.actionId || !body.action) {
    return Response.json(
      { error: "action et actionId requis" },
      { status: 400 }
    );
  }

  try {
    if (body.action === "cancel") {
      await cancelFilesMutationAction({
        actionId: body.actionId,
        userId,
      });
      return Response.json({ ok: true });
    }

    if (!body.confirmationToken) {
      return Response.json(
        { error: "confirmationToken requis" },
        { status: 400 }
      );
    }

    await confirmFilesMutationAction({
      actionId: body.actionId,
      confirmationToken: body.confirmationToken,
      userId,
    });
    return Response.json({ ok: true });
  } catch (err) {
    return Response.json(
      { error: err instanceof Error ? err.message : "Erreur" },
      { status: 400 }
    );
  }
});
