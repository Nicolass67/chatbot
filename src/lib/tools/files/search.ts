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
    "Recherche des fichiers locaux par nom/métadonnées dans les roots autorisées. Retourne des fileId (pas de chemins bruts) et des métadonnées légères.",
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

    return withUntrustedFileNotice({
      query: input.query,
      filesScanned,
      results: hits.map((h) => ({
        fileId: h.fileId,
        filename: h.filename,
        relativePath: h.relativePath,
        rootId: h.rootId,
        sizeBytes: h.sizeBytes,
        mtimeMs: h.mtimeMs,
        extension: h.extension,
        score: h.score,
        snippet: h.snippet,
      })),
    });
  },
};
