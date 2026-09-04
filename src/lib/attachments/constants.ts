export const IMAGE_MIMES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
]);

export const IMAGE_EXTENSIONS = new Set([".jpg", ".jpeg", ".png", ".webp"]);

export const DOCUMENT_MIMES = new Set([
  "application/pdf",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "text/plain",
  "text/markdown",
  "text/csv",
  "application/json",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
]);

export const DOCUMENT_EXTENSIONS = new Set([
  ".pdf",
  ".docx",
  ".txt",
  ".md",
  ".markdown",
  ".csv",
  ".json",
  ".xlsx",
]);

export const DEFAULT_MAX_ATTACHMENT_BYTES = 20 * 1024 * 1024; // 20 MB
export const DEFAULT_MAX_ATTACHMENTS = 10;
export const CHUNK_SIZE = 800;
export const CHUNK_OVERLAP = 120;
export const DIRECT_INJECT_MAX_CHARS = 4000;

export function getExtension(filename: string): string {
  const idx = filename.lastIndexOf(".");
  return idx >= 0 ? filename.slice(idx).toLowerCase() : "";
}

export function formatFileSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} o`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} Ko`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} Mo`;
}

export function classifyAttachment(
  filename: string,
  mimeType: string
): "image" | "document" | null {
  const ext = getExtension(filename);
  if (IMAGE_MIMES.has(mimeType) || IMAGE_EXTENSIONS.has(ext)) return "image";
  if (DOCUMENT_MIMES.has(mimeType) || DOCUMENT_EXTENSIONS.has(ext)) {
    return "document";
  }
  return null;
}
