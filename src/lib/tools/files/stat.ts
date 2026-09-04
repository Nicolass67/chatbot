import { z } from "zod";
import { getFilesCapabilities, isFilesFeatureEnabled } from "@/lib/files/feature";
import { requireFilesUserId } from "@/lib/files/helpers";
import { extensionOf, resolveFileReference } from "@/lib/files/resolve";
import type { Tool } from "../types";

const inputSchema = z.object({
  fileId: z.string().describe("fileId serveur du fichier ou dossier"),
});

export const fileStatTool: Tool<
  z.infer<typeof inputSchema>,
  Record<string, unknown>
> = {
  name: "file_stat",
  description: "Métadonnées d'un fichier local via fileId (sans contenu).",
  inputSchema,
  preferredRuntime: "local",
  async execute(input, ctx) {
    if (!isFilesFeatureEnabled() || !getFilesCapabilities().read) {
      throw new Error("Files read désactivé.");
    }
    const userId = requireFilesUserId(ctx);
    const resolved = await resolveFileReference(userId, input.fileId);
    return {
      fileId: resolved.fileId,
      name: resolved.displayName,
      relativePath: resolved.relativePath,
      rootId: resolved.rootId,
      isDirectory: resolved.isDirectory,
      sizeBytes: resolved.sizeBytes,
      mtimeMs: resolved.mtimeMs,
      extension: extensionOf(resolved.displayName),
      access: {
        canAccessPath: resolved.access.canAccessPath,
        canExposeToLlm: resolved.access.canExposeToLlm,
        canMutate: resolved.access.canMutate,
      },
    };
  },
};
