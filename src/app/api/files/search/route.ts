export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { isFilesFeatureEnabled } from "@/lib/files/feature";
import { searchFileIndexPassages } from "@/lib/files/index-service";
import { searchMetadata } from "@/lib/files/provider";
import { mintFileReference } from "@/lib/files/references";
import { apiErrorResponse } from "@/lib/http/api-error";
import {
  ensureDefaultRoots,
  getFileRoot,
  listEnabledFileRoots,
} from "@/lib/files/roots";

type SearchMode = "name" | "content" | "all";

export const GET = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isFilesFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Files désactivé");
  }
  const userId = auth.userId ?? "local";
  await ensureDefaultRoots(userId);
  const sp = new URL(request.url).searchParams;
  const query = sp.get("q") ?? "";
  const rootId = sp.get("root") ?? undefined;
  const extension = sp.get("ext") ?? undefined;
  const modeParam = sp.get("mode") ?? "name";
  const mode: SearchMode =
    modeParam === "content" || modeParam === "all" ? modeParam : "name";

  let roots = await listEnabledFileRoots(userId);
  if (rootId) {
    const root = await getFileRoot(userId, rootId);
    if (!root?.enabled) {
      return Response.json({ error: "Root invalide" }, { status: 400 });
    }
    roots = [root];
  }

  if (!query.trim()) {
    return Response.json({ results: [], filesScanned: 0, mode });
  }

  const byPath = new Map<
    string,
    {
      fileId: string;
      name: string;
      filename: string;
      relativePath: string;
      rootId: string;
      sizeBytes: number;
      mtimeMs: number;
      extension: string;
      isDirectory: boolean;
      score: number;
      snippet?: string;
      matchSource: "name" | "content";
    }
  >();

  let filesScanned = 0;

  if (mode === "name" || mode === "all") {
    const { hits, filesScanned: scanned } = await searchMetadata({
      userId,
      roots,
      filters: {
        query,
        extensions: extension ? [extension] : undefined,
      },
    });
    filesScanned = scanned;
    for (const hit of hits) {
      const key = `${hit.rootId}:${hit.relativePath}`;
      byPath.set(key, {
        fileId: hit.fileId,
        name: hit.filename,
        filename: hit.filename,
        relativePath: hit.relativePath,
        rootId: hit.rootId,
        sizeBytes: hit.sizeBytes,
        mtimeMs: hit.mtimeMs,
        extension: hit.extension,
        isDirectory: false,
        score: hit.score,
        snippet: hit.snippet,
        matchSource: "name",
      });
    }
  }

  if (mode === "content" || mode === "all") {
    for (const root of roots) {
      const passages = await searchFileIndexPassages({
        userId,
        rootId: root.id,
        query,
        limit: 25,
      });
      for (const passage of passages) {
        const key = `${root.id}:${passage.relativePath}`;
        const existing = byPath.get(key);
        if (existing) {
          if (mode === "all" && existing.matchSource === "name") {
            existing.snippet = passage.content.slice(0, 180);
            // keep name match but enrich snippet from content
          } else {
            existing.snippet = passage.content.slice(0, 180);
            existing.score = Math.max(existing.score, -passage.score);
          }
          continue;
        }
        const displayName =
          passage.relativePath.split("/").pop() || passage.relativePath;
        const ref = await mintFileReference({
          userId,
          rootId: root.id,
          relativePath: passage.relativePath,
          displayName,
          sizeBytes: 0,
          mtimeMs: 0,
        });
        const extIdx = displayName.lastIndexOf(".");
        byPath.set(key, {
          fileId: ref.id,
          name: displayName,
          filename: displayName,
          relativePath: passage.relativePath,
          rootId: root.id,
          sizeBytes: 0,
          mtimeMs: 0,
          extension: extIdx > 0 ? displayName.slice(extIdx) : "",
          isDirectory: false,
          score: -passage.score,
          snippet: passage.content.slice(0, 180),
          matchSource: "content",
        });
      }
    }
  }

  const results = [...byPath.values()].sort((a, b) => b.score - a.score);

  return Response.json({
    results,
    filesScanned,
    mode,
    hint:
      mode === "content"
        ? "Résultats FTS uniquement (fichiers indexés)."
        : undefined,
  });
});
