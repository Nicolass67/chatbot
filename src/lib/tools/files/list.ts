import { z } from "zod";
import { getFilesCapabilities, isFilesFeatureEnabled } from "@/lib/files/feature";
import { requireFilesUserId, withUntrustedFileNotice } from "@/lib/files/helpers";
import { listDirectory } from "@/lib/files/provider";
import { resolveFileReference } from "@/lib/files/resolve";
import { getFileRoot } from "@/lib/files/roots";
import type { Tool } from "../types";

const inputSchema = z.object({
  fileId: z
    .string()
    .describe("fileId d'un dossier (référence serveur), jamais un chemin absolu"),
  limit: z.number().optional().describe("Nombre max d'entrées"),
});

export const fileListTool: Tool<
  z.infer<typeof inputSchema>,
  Record<string, unknown>
> = {
  name: "file_list",
  description:
    "Liste le contenu d'un dossier local via fileId. Ne pas fournir de chemin filesystem.",
  inputSchema,
  preferredRuntime: "local",
  async execute(input, ctx) {
    if (!isFilesFeatureEnabled() || !getFilesCapabilities().read) {
      throw new Error("Files read désactivé.");
    }
    const userId = requireFilesUserId(ctx);
    const resolved = await resolveFileReference(userId, input.fileId);
    if (!resolved.isDirectory) {
      throw new Error("fileId ne pointe pas vers un dossier.");
    }
    const root = await getFileRoot(userId, resolved.rootId);
    if (!root) throw new Error("Root introuvable.");
    const result = await listDirectory({
      userId,
      root,
      relativePath: resolved.relativePath,
      limit: input.limit,
    });
    return withUntrustedFileNotice({
      fileId: resolved.fileId,
      relativePath: resolved.relativePath,
      entries: result.entries,
      nextCursor: result.nextCursor,
      totalListed: result.totalListed,
    });
  },
};
