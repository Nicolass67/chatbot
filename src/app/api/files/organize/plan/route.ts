export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { isFilesFeatureEnabled } from "@/lib/files/feature";
import {
  generateOrganizePlan,
  type OrganizePlanItem,
} from "@/lib/files/organize-plan";
import { apiErrorResponse } from "@/lib/http/api-error";

export const POST = withAuth(apiAuthGuard, async (request) => {
  if (!isFilesFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Files désactivé");
  }

  let body: {
    rootId?: string;
    rootRelativePath?: string;
    items?: OrganizePlanItem[];
    protectedPaths?: string[];
    instruction?: string | null;
  };

  try {
    body = (await request.json()) as typeof body;
  } catch {
    return apiErrorResponse("VALIDATION_ERROR", "JSON invalide");
  }

  const rootId = body.rootId?.trim();
  if (!rootId) {
    return apiErrorResponse("VALIDATION_ERROR", "rootId requis");
  }

  const items = Array.isArray(body.items) ? body.items : [];
  if (items.length === 0) {
    return apiErrorResponse(
      "VALIDATION_ERROR",
      "items requis (inventaire non vide)"
    );
  }

  try {
    const plan = await generateOrganizePlan({
      rootId,
      rootRelativePath: body.rootRelativePath?.replace(/\\/g, "/") ?? "",
      items,
      protectedPaths: Array.isArray(body.protectedPaths)
        ? body.protectedPaths.filter((p): p is string => typeof p === "string")
        : [],
      instruction: body.instruction,
    });
    return Response.json(plan);
  } catch (err) {
    const message =
      err instanceof Error ? err.message : "Échec génération du plan";
    const code =
      err && typeof err === "object" && "code" in err
        ? String((err as { code?: string }).code)
        : "";
    if (code === "MODEL_UNAVAILABLE") {
      return apiErrorResponse("AI_ERROR", message, { status: 503 });
    }
    if (code === "INVALID_AI_RESPONSE") {
      return apiErrorResponse("AI_ERROR", message, { status: 503 });
    }
    return apiErrorResponse("AI_ERROR", message, { status: 503 });
  }
});
