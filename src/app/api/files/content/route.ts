export const runtime = "nodejs";

import fs from "node:fs";
import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import {
  extractTextFromFile,
  guessMimeFromFilename,
} from "@/lib/documents/extract";
import { isFilesFeatureEnabled } from "@/lib/files/feature";
import { extensionOf, resolveFileReference } from "@/lib/files/resolve";
import { apiErrorResponse } from "@/lib/http/api-error";

const TEXT_EXTS = new Set([
  ".txt",
  ".md",
  ".markdown",
  ".json",
  ".csv",
  ".js",
  ".ts",
  ".tsx",
  ".jsx",
  ".py",
  ".rs",
  ".go",
  ".css",
  ".html",
  ".xml",
  ".yml",
  ".yaml",
  ".toml",
  ".sh",
  ".ps1",
  ".log",
  ".ini",
]);

const IMAGE_EXTS = new Set([".png", ".jpg", ".jpeg", ".webp", ".gif"]);
const EXTRACT_EXTS = new Set([".docx", ".xlsx"]);
const PDF_MAX_BYTES = 40 * 1024 * 1024;

const MAX_TEXT_CHARS = 120_000;
const MAX_EXTRACT_CHARS = 40_000;

export const GET = withAuth(apiAuthGuard, async (request, auth) => {
  if (!isFilesFeatureEnabled()) {
    return apiErrorResponse("FEATURE_DISABLED", "Files désactivé");
  }
  const userId = auth.userId ?? "local";
  const fileId = new URL(request.url).searchParams.get("fileId");
  if (!fileId) {
    return Response.json({ error: "fileId requis" }, { status: 400 });
  }

  try {
    const resolved = await resolveFileReference(userId, fileId);
    if (resolved.isDirectory) {
      return Response.json({ error: "Pas un fichier" }, { status: 400 });
    }
    if (!resolved.access.canAccessPath) {
      return Response.json(
        {
          error: "Accès refusé",
          code: "FORBIDDEN",
          reasonCodes: resolved.access.reasonCodes,
        },
        { status: 403 }
      );
    }

    const ext =
      extensionOf(resolved.relativePath) ||
      extensionOf(resolved.displayName);
    const mime = guessMimeFromFilename(resolved.displayName) || "application/octet-stream";

    // Téléchargement brut (ex. PJ mail) — pas d’extraction / aperçu.
    if (new URL(request.url).searchParams.get("download") === "1") {
      const buf = fs.readFileSync(resolved.absolutePath);
      const maxBytes = 50 * 1024 * 1024;
      if (buf.length > maxBytes) {
        return Response.json(
          { error: "Fichier trop volumineux (max 50 Mo)" },
          { status: 413 }
        );
      }
      return new Response(buf, {
        headers: {
          "Content-Type": mime,
          "Content-Disposition": `attachment; filename="${encodeURIComponent(resolved.displayName)}"`,
          "Cache-Control": "private, max-age=60",
          "X-Files-Kind": "download",
          "X-Files-Name": encodeURIComponent(resolved.displayName),
          "X-Files-Size": String(buf.length),
        },
      });
    }

    if (IMAGE_EXTS.has(ext)) {
      const buf = fs.readFileSync(resolved.absolutePath);
      if (buf.length > 12 * 1024 * 1024) {
        return Response.json({ error: "Image trop volumineuse" }, { status: 413 });
      }
      return new Response(buf, {
        headers: {
          "Content-Type": mime.startsWith("image/") ? mime : "application/octet-stream",
          "Cache-Control": "private, max-age=60",
          "X-Files-Kind": "image",
        },
      });
    }

    if (ext === ".pdf") {
      const buf = fs.readFileSync(resolved.absolutePath);
      if (buf.length > PDF_MAX_BYTES) {
        return Response.json(
          { error: "PDF trop volumineux pour l’aperçu" },
          { status: 413 }
        );
      }
      const wantExtract =
        new URL(request.url).searchParams.get("extract") === "1";
      if (wantExtract) {
        const text = await extractTextFromFile(
          resolved.absolutePath,
          "application/pdf",
          resolved.displayName
        );
        const truncated = text.length > MAX_EXTRACT_CHARS;
        return Response.json({
          kind: "extract",
          language: "text",
          text: truncated ? text.slice(0, MAX_EXTRACT_CHARS) : text,
          truncated,
          mime: "application/pdf",
          name: resolved.displayName,
          sizeBytes: resolved.sizeBytes,
          notice: "Extraction texte du PDF.",
          canExposeToLlm: resolved.access.canExposeToLlm,
        });
      }
      return new Response(buf, {
        headers: {
          "Content-Type": "application/pdf",
          "Content-Disposition": `inline; filename="${encodeURIComponent(resolved.displayName)}"`,
          "Cache-Control": "private, max-age=60",
          "X-Files-Kind": "pdf",
        },
      });
    }

    if (TEXT_EXTS.has(ext) || mime.startsWith("text/")) {
      const raw = fs.readFileSync(resolved.absolutePath, "utf8");
      const truncated = raw.length > MAX_TEXT_CHARS;
      const text = truncated ? raw.slice(0, MAX_TEXT_CHARS) : raw;
      const kind =
        ext === ".md" || ext === ".markdown"
          ? "markdown"
          : ext === ".json"
            ? "json"
            : ext === ".csv"
              ? "csv"
              : "text";
      return Response.json({
        kind,
        language: ext.replace(".", "") || "text",
        text,
        truncated,
        mime,
        name: resolved.displayName,
        sizeBytes: resolved.sizeBytes,
        canExposeToLlm: resolved.access.canExposeToLlm,
      });
    }

    if (EXTRACT_EXTS.has(ext)) {
      const text = await extractTextFromFile(
        resolved.absolutePath,
        mime,
        resolved.displayName
      );
      const truncated = text.length > MAX_EXTRACT_CHARS;
      return Response.json({
        kind: "extract",
        language: "text",
        text: truncated ? text.slice(0, MAX_EXTRACT_CHARS) : text,
        truncated,
        mime,
        name: resolved.displayName,
        sizeBytes: resolved.sizeBytes,
        notice:
          "Aperçu texte (extraction) — rendu natif PDF/Office non disponible en V1.",
        canExposeToLlm: resolved.access.canExposeToLlm,
      });
    }

    return Response.json({
      kind: "unsupported",
      name: resolved.displayName,
      mime,
      sizeBytes: resolved.sizeBytes,
      extension: ext,
      message: `Aperçu non disponible pour ${ext || "ce type"}.`,
      canExposeToLlm: resolved.access.canExposeToLlm,
    });
  } catch (err) {
    return Response.json(
      { error: err instanceof Error ? err.message : "Erreur" },
      { status: 400 }
    );
  }
});
