export const runtime = "nodejs";

import { z } from "zod";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { isFilesFeatureEnabled } from "@/lib/files/feature";
import { writeFileUnderRoot } from "@/lib/files/provider";
import { getFileRoot } from "@/lib/files/roots";
import { mintFileReference } from "@/lib/files/references";
import { FilesError } from "@/lib/files/types";
import { SENSITIVE_NAME_PATTERNS } from "@/lib/files/constants";
import { apiErrorResponse } from "@/lib/http/api-error";

const MAX_UPLOAD_BYTES = 50 * 1024 * 1024;

function safeBasename(name: string): string {
  const base = name.replace(/\\/g, "/").split("/").pop() ?? "fichier";
  const cleaned = base.replace(/[<>:"|?*\u0000-\u001f]/g, "_").trim();
  if (!cleaned || cleaned === "." || cleaned === "..") {
    throw new FilesError("PATH_ESCAPE", "Nom de fichier invalide.");
  }
  if (SENSITIVE_NAME_PATTERNS.some((p) => p.test(cleaned))) {
    throw new FilesError(
      "SENSITIVE_PATTERN",
      "Ce nom de fichier est refusé (sensible)."
    );
  }
  return cleaned;
}

export const POST = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isFilesFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Files désactivé");
  }
  const userId = auth.userId ?? "local";

  try {
    const form = await request.formData();
    const rootId = String(form.get("rootId") ?? "");
    const destDir = String(form.get("destRelativePath") ?? "")
      .replace(/\\/g, "/")
      .replace(/^\/+|\/+$/g, "");
    const overwrite = String(form.get("overwrite") ?? "") === "true";

    if (!rootId) {
      return Response.json({ error: "rootId requis" }, { status: 400 });
    }

    const root = await getFileRoot(userId, rootId);
    if (!root?.enabled) {
      return Response.json({ error: "Root invalide" }, { status: 400 });
    }

    const uploaded: Array<{
      fileId: string;
      name: string;
      relativePath: string;
      sizeBytes: number;
    }> = [];

    const entries = form.getAll("files");
    if (entries.length === 0) {
      return Response.json({ error: "Aucun fichier" }, { status: 400 });
    }

    for (const entry of entries) {
      if (!(entry instanceof File)) continue;
      if (entry.size > MAX_UPLOAD_BYTES) {
        return Response.json(
          {
            error: `Fichier trop volumineux (max ${MAX_UPLOAD_BYTES / (1024 * 1024)} Mo)`,
            name: entry.name,
          },
          { status: 400 }
        );
      }
      const name = safeBasename(entry.name);
      const relativePath = destDir ? `${destDir}/${name}` : name;
      const buf = Buffer.from(await entry.arrayBuffer());
      writeFileUnderRoot({
        rootAbsolute: root.absolutePath,
        relativePath,
        data: buf,
        overwrite,
      });
      const st = { size: buf.length, mtimeMs: Date.now() };
      const ref = await mintFileReference({
        userId,
        rootId: root.id,
        relativePath,
        displayName: name,
        sizeBytes: st.size,
        mtimeMs: Math.floor(st.mtimeMs),
      });
      uploaded.push({
        fileId: ref.id,
        name,
        relativePath,
        sizeBytes: st.size,
      });
    }

    if (uploaded.length === 0) {
      return Response.json({ error: "Aucun fichier valide" }, { status: 400 });
    }

    return Response.json({ uploaded });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return Response.json({ error: "Requête invalide" }, { status: 400 });
    }
    if (error instanceof FilesError) {
      return Response.json(
        { error: error.message, code: error.code },
        { status: 400 }
      );
    }
    const message =
      error instanceof Error ? error.message : "Échec de l'enregistrement";
    console.error("[files/upload]", error);
    return Response.json({ error: message }, { status: 500 });
  }
});
