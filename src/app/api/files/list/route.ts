export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { isFilesFeatureEnabled } from "@/lib/files/feature";
import { listIndexedRelativePaths } from "@/lib/files/index-service";
import { listDirectory } from "@/lib/files/provider";
import { mintFileReference } from "@/lib/files/references";
import { resolveFileReference, resolvePathToFile } from "@/lib/files/resolve";
import { getFileRoot } from "@/lib/files/roots";
import { apiErrorResponse } from "@/lib/http/api-error";

async function enrichIndexed(
  userId: string,
  rootId: string,
  entries: Array<{ relativePath: string; indexed?: boolean }>
) {
  if (entries.length === 0) return;
  const indexed = await listIndexedRelativePaths(
    userId,
    rootId,
    entries.map((e) => e.relativePath)
  );
  for (const e of entries) {
    e.indexed = indexed.has(e.relativePath.replace(/\\/g, "/"));
  }
}

export const GET = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isFilesFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Files désactivé");
  }
  const userId = auth.userId ?? "local";
  const sp = new URL(request.url).searchParams;
  const fileId = sp.get("fileId");
  const rootId = sp.get("root");
  const relativePath = sp.get("path") ?? "";
  const cursor = sp.get("cursor") ?? undefined;
  const limitRaw = Number(sp.get("limit") ?? "200");
  const limit = Number.isFinite(limitRaw) ? limitRaw : 200;

  try {
    if (fileId) {
      const resolved = await resolveFileReference(userId, fileId);
      if (!resolved.isDirectory) {
        return Response.json({ error: "Pas un dossier" }, { status: 400 });
      }
      const root = await getFileRoot(userId, resolved.rootId);
      if (!root) return apiErrorResponse("NOT_FOUND", "Root introuvable");
      const result = await listDirectory({
        userId,
        root,
        relativePath: resolved.relativePath,
        limit,
        cursor,
      });
      await enrichIndexed(userId, root.id, result.entries);
      return Response.json({
        fileId: resolved.fileId,
        entries: result.entries,
        nextCursor: result.nextCursor,
        totalListed: result.totalListed,
      });
    }

    if (!rootId) {
      return Response.json({ error: "root ou fileId requis" }, { status: 400 });
    }

    const { root, relativePath: rel, stat } = await resolvePathToFile(
      userId,
      rootId,
      relativePath
    );
    if (!stat.isDirectory()) {
      return Response.json({ error: "Pas un dossier" }, { status: 400 });
    }
    const dirRef = await mintFileReference({
      userId,
      rootId: root.id,
      relativePath: rel,
      displayName: rel.split("/").pop() || root.label,
      sizeBytes: 0,
      mtimeMs: Math.floor(stat.mtimeMs),
    });
    const result = await listDirectory({
      userId,
      root,
      relativePath: rel,
      limit,
      cursor,
    });
    await enrichIndexed(userId, root.id, result.entries);
    return Response.json({
      fileId: dirRef.id,
      entries: result.entries,
      nextCursor: result.nextCursor,
      totalListed: result.totalListed,
    });
  } catch (err) {
    return Response.json(
      { error: err instanceof Error ? err.message : "Erreur" },
      { status: 400 }
    );
  }
});
