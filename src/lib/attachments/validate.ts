import path from "node:path";
import { nanoid } from "nanoid";
import {
  classifyAttachment,
  DEFAULT_MAX_ATTACHMENT_BYTES,
  getExtension,
} from "./constants";

const SAFE_FILENAME = /^[a-zA-Z0-9._-]+$/;

export function sanitizeFilename(original: string): string {
  const base = path.basename(original).replace(/[^\w.\-()+ ]/g, "_");
  const trimmed = base.slice(0, 120) || "file";
  const ext = getExtension(trimmed);
  const name = ext ? trimmed.slice(0, -ext.length) : trimmed;
  return `${name.slice(0, 80)}${ext}`;
}

export function buildStoragePath(
  attachmentsRoot: string,
  conversationId: string,
  filename: string
): string {
  const safeName = `${nanoid(12)}_${sanitizeFilename(filename)}`;
  return path.join(attachmentsRoot, conversationId, safeName);
}

export interface ValidateFileInput {
  filename: string;
  mimeType: string;
  sizeBytes: number;
  maxBytes?: number;
}

export function validateFile(input: ValidateFileInput): {
  ok: true;
  type: "image" | "document";
} | { ok: false; error: string } {
  if (input.sizeBytes <= 0) {
    return { ok: false, error: "Fichier vide" };
  }
  const max = input.maxBytes ?? DEFAULT_MAX_ATTACHMENT_BYTES;
  if (input.sizeBytes > max) {
    return {
      ok: false,
      error: `Fichier trop volumineux (max ${Math.round(max / 1024 / 1024)} Mo)`,
    };
  }

  const type = classifyAttachment(input.filename, input.mimeType);
  if (!type) {
    return { ok: false, error: "Type de fichier non supporté" };
  }

  const ext = getExtension(input.filename);
  if (ext && !SAFE_FILENAME.test(path.basename(input.filename))) {
    // still ok if we sanitized - block path traversal
  }
  if (input.filename.includes("..") || input.filename.includes("/") || input.filename.includes("\\")) {
    return { ok: false, error: "Nom de fichier invalide" };
  }

  return { ok: true, type };
}
