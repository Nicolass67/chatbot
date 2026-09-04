export const runtime = "nodejs";

import { z } from "zod";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { isFilesFeatureEnabled } from "@/lib/files/feature";
import { filesAssistantChat } from "@/lib/files/ai-service";
import { apiErrorResponse } from "@/lib/http/api-error";

const bodySchema = z.object({
  message: z.string().min(1).max(4000),
  rootId: z.string().min(1),
  currentPath: z.string().max(2000).optional(),
  selectedFileIds: z.array(z.string().min(1)).max(20).optional(),
  model: z.string().optional(),
  pendingUploads: z
    .array(
      z.object({
        name: z.string().min(1).max(500),
        sizeBytes: z.number().int().nonnegative(),
      })
    )
    .max(20)
    .optional(),
});

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isFilesFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Files désactivé");
  }
  const userId = auth.userId ?? "local";
  try {
    const body = bodySchema.parse(await request.json());
    const result = await filesAssistantChat({
      userId,
      message: body.message,
      rootId: body.rootId,
      currentPath: body.currentPath,
      selectedFileIds: body.selectedFileIds,
      model: body.model,
      pendingUploads: body.pendingUploads,
    });
    return Response.json(result);
  } catch (error) {
    if (error instanceof z.ZodError) {
      return apiErrorResponse("VALIDATION_ERROR", "Requête invalide");
    }
    const message =
      error instanceof Error ? error.message : "Erreur assistant Files";
    console.error("[files/ai/chat]", error);
    return apiErrorResponse("AI_ERROR", message);
  }
});
