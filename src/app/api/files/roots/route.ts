export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { isFilesFeatureEnabled } from "@/lib/files/feature";
import { apiErrorResponse } from "@/lib/http/api-error";
import {
  addFileRoot,
  ensureDefaultRoots,
  listFileRoots,
  removeFileRoot,
  setFileRootEnabled,
} from "@/lib/files/roots";

export const GET = withAuth(apiAuthGuard, async (_request, auth) => {
  if (!isFilesFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Files désactivé", { details: { enabled: false } });
  }
  const userId = auth.userId ?? "local";
  await ensureDefaultRoots(userId);
  const roots = await listFileRoots(userId);
  return Response.json({ enabled: true, roots });
});

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isFilesFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Files désactivé");
  }
  const userId = auth.userId ?? "local";
  const body = (await request.json()) as {
    label?: string;
    absolutePath?: string;
  };
  if (!body.absolutePath?.trim()) {
    return apiErrorResponse("VALIDATION_ERROR", "absolutePath requis");
  }
  try {
    const root = await addFileRoot({
      userId,
      label: body.label ?? "",
      absolutePath: body.absolutePath,
    });
    return Response.json({ root });
  } catch (err) {
    return Response.json(
      { error: err instanceof Error ? err.message : "Erreur" },
      { status: 400 }
    );
  }
});

export const PATCH = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isFilesFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Files désactivé");
  }
  const userId = auth.userId ?? "local";
  const body = (await request.json()) as {
    rootId?: string;
    enabled?: boolean;
  };
  if (!body.rootId || typeof body.enabled !== "boolean") {
    return apiErrorResponse("VALIDATION_ERROR", "rootId et enabled requis");
  }
  try {
    const root = await setFileRootEnabled(userId, body.rootId, body.enabled);
    return Response.json({ root });
  } catch (err) {
    return apiErrorResponse(
      "VALIDATION_ERROR",
      err instanceof Error ? err.message : "Erreur"
    );
  }
});

export const DELETE = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isFilesFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Files désactivé");
  }
  const userId = auth.userId ?? "local";
  const rootId = new URL(request.url).searchParams.get("rootId");
  if (!rootId) {
    return apiErrorResponse("VALIDATION_ERROR", "rootId requis");
  }
  try {
    await removeFileRoot(userId, rootId);
    return Response.json({ ok: true });
  } catch (err) {
    return apiErrorResponse(
      "VALIDATION_ERROR",
      err instanceof Error ? err.message : "Erreur"
    );
  }
});
