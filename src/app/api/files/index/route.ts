export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { isFilesFeatureEnabled } from "@/lib/files/feature";
import { indexRootFiles, purgeIndexForRoot } from "@/lib/files/index-service";
import { getFileRoot } from "@/lib/files/roots";
import { apiErrorResponse } from "@/lib/http/api-error";

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isFilesFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Files désactivé");
  }
  const userId = auth.userId ?? "local";
  const body = (await request.json()) as {
    rootId?: string;
    purge?: boolean;
  };
  if (!body.rootId) {
    return Response.json({ error: "rootId requis" }, { status: 400 });
  }
  const root = await getFileRoot(userId, body.rootId);
  if (!root?.enabled) {
    return Response.json({ error: "Root invalide" }, { status: 400 });
  }

  if (body.purge) {
    await purgeIndexForRoot(userId, root.id);
    return Response.json({ ok: true, purged: true });
  }

  const result = await indexRootFiles({ userId, root });
  return Response.json(result);
});
