import { searchFileIndexPassages } from "@/lib/files/index-service";
import { mintFileReference } from "@/lib/files/references";
import { z } from "zod";
import { getFilesCapabilities, isFilesFeatureEnabled } from "@/lib/files/feature";
import {
  requireFilesUserId,
  withUntrustedFileNotice,
} from "@/lib/files/helpers";
import { searchMetadata } from "@/lib/files/provider";
import { requireEnabledRoots } from "@/lib/files/resolve";
import { ensureDefaultRoots, getFileRoot } from "@/lib/files/roots";
import type { Tool } from "../types";

const inputSchema = z.object({
  query: z.string().describe("Mots-clés de recherche (nom de fichier)"),
  rootId: z.string().optional().describe("Restreindre à une rootId"),
  extension: z
    .string()
    .optional()
    .describe("Extension sans ou avec point, ex: pdf"),
});

export const fileSearchTool: Tool<
  z.infer<typeof inputSchema>,
  Record<string, unknown>
> = {
  name: "file_search",
  description:
    "Recherche UNIQUEMENT des fichiers locaux (PDF, factures, documents sur le PC) par nom/métadonnées dans les roots autorisées. N'utilise JAMAIS cet outil pour des infos Internet (adresses, restaurants, actualités, sites web) — utilise web_search.",
  inputSchema,
  preferredRuntime: "local",
  async execute(input, ctx) {
    if (!isFilesFeatureEnabled()) {
      throw new Error("Files désactivé.");
    }
    if (!getFilesCapabilities().search) {
      throw new Error("Capacité search désactivée.");
    }
    const userId = requireFilesUserId(ctx);
    await ensureDefaultRoots(userId);
    let roots = await requireEnabledRoots(userId);
    if (input.rootId) {
      const root = await getFileRoot(userId, input.rootId);
      if (!root?.enabled) throw new Error("Root invalide.");
      roots = [root];
    }

    const { hits, filesScanned } = await searchMetadata({
      userId,
      roots,
      filters: {
        query: input.query,
        extensions: input.extension ? [input.extension] : undefined,
      },
    });

    const byId = new Map<
      string,
      {
        fileId: string;
        filename: string;
        relativePath: string;
        rootId: string;
        sizeBytes: number;
        mtimeMs: number;
        extension: string;
        score: number;
        snippet?: string;
        source: "metadata" | "content" | "hybrid";
      }
    >();
    for (const h of hits) {
      byId.set(h.fileId, {
        fileId: h.fileId,
        filename: h.filename,
        relativePath: h.relativePath,
        rootId: h.rootId,
        sizeBytes: h.sizeBytes,
        mtimeMs: h.mtimeMs,
        extension: h.extension,
        score: h.score,
        snippet: h.snippet,
        source: "metadata",
      });
    }
    for (const root of roots) {
      try {
        const passages = await searchFileIndexPassages({
          userId,
          rootId: root.id,
          query: input.query,
          limit: 8,
        });
        for (const p of passages) {
          const filename =
            p.relativePath.split("/").filter(Boolean).pop() ?? p.relativePath;
          const existing = [...byId.values()].find(
            (x) => x.rootId === root.id && x.relativePath === p.relativePath
          );
          if (existing) {
            existing.score = Math.max(existing.score, 50 + Math.abs(p.score || 0));
            existing.snippet = existing.snippet || p.content.slice(0, 200);
            existing.source = "hybrid";
            continue;
          }
          try {
            const ref = await mintFileReference({
              userId,
              rootId: root.id,
              relativePath: p.relativePath,
              displayName: filename,
              sizeBytes: 0,
              mtimeMs: Date.now(),
            });
            byId.set(ref.id, {
              fileId: ref.id,
              filename,
              relativePath: p.relativePath,
              rootId: root.id,
              sizeBytes: 0,
              mtimeMs: Date.now(),
              extension: filename.includes(".")
                ? filename.slice(filename.lastIndexOf(".") + 1)
                : "",
              score: 45 + Math.abs(p.score || 0),
              snippet: p.content.slice(0, 200),
              source: "content",
            });
          } catch {
            /* ignore mint failures */
          }
        }
      } catch {
        /* index optionnel */
      }
    }
    const merged = [...byId.values()]
      .sort((a, b) => b.score - a.score)
      .slice(0, 25);
    return withUntrustedFileNotice({
      query: input.query,
      filesScanned,
      retrieval: "hybrid_metadata_fts",
      results: merged,
    });
  },
};
