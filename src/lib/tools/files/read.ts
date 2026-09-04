import path from "node:path";
import { z } from "zod";
import {
  extractTextFromFile,
  guessMimeFromFilename,
  normalizeText,
} from "@/lib/documents/extract";
import { LIMITS } from "@/lib/files/constants";
import { getFilesCapabilities, isFilesFeatureEnabled } from "@/lib/files/feature";
import {
  requireFilesUserId,
  withUntrustedFileNotice,
  wrapFileContentForPrompt,
} from "@/lib/files/helpers";
import { resolveFileReference } from "@/lib/files/resolve";
import type { Tool } from "../types";

const inputSchema = z.object({
  fileId: z.string().describe("fileId serveur — jamais un chemin absolu"),
  maxChars: z.number().optional().describe("Limite de caractères extraits"),
});

function maxBytesForExt(ext: string): number {
  if (ext === ".pdf") return LIMITS.pdfBytes;
  if (ext === ".docx" || ext === ".xlsx") return LIMITS.officeBytes;
  return LIMITS.textExtractBytes;
}

export const fileReadTool: Tool<
  z.infer<typeof inputSchema>,
  Record<string, unknown>
> = {
  name: "file_read",
  description:
    "Lit et extrait le texte d'un fichier local via fileId. Contenu non fiable (untrusted).",
  inputSchema,
  preferredRuntime: "local",
  async execute(input, ctx) {
    if (!isFilesFeatureEnabled() || !getFilesCapabilities().read) {
      throw new Error("Files read désactivé.");
    }
    const userId = requireFilesUserId(ctx);
    const resolved = await resolveFileReference(userId, input.fileId, {
      requireExpose: true,
    });
    if (resolved.isDirectory) {
      throw new Error("Impossible de lire un dossier avec file_read.");
    }

    const ext = path.extname(resolved.displayName).toLowerCase();
    if (resolved.sizeBytes > maxBytesForExt(ext)) {
      throw new Error(
        `Fichier trop volumineux pour extraction (${resolved.sizeBytes} o).`
      );
    }

    const mime = guessMimeFromFilename(resolved.displayName);
    let text: string;
    try {
      text = await extractTextFromFile(
        resolved.absolutePath,
        mime,
        resolved.displayName
      );
    } catch {
      throw new Error(`Extraction non supportée pour ${ext || mime}.`);
    }

    const maxChars = input.maxChars ?? LIMITS.readDefaultMaxChars;
    const normalized = normalizeText(text);
    const truncated = normalized.length > maxChars;
    const content = truncated
      ? `${normalized.slice(0, maxChars)}…`
      : normalized;

    const visionSuggested =
      (!content || content.length < 40) &&
      [".jpg", ".jpeg", ".png", ".webp", ".pdf"].includes(ext);

    return withUntrustedFileNotice({
      fileId: resolved.fileId,
      relativePath: resolved.relativePath,
      truncated,
      charCount: content.length,
      visionSuggested,
      wrappedContent: wrapFileContentForPrompt({
        fileId: resolved.fileId,
        relativePath: resolved.relativePath,
        content,
      }),
      contentPreview: content.slice(0, 500),
    });
  },
};
