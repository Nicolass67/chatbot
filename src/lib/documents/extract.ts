import fs from "node:fs";
import path from "node:path";

export const DOC_CHUNK_SIZE = 800;
export const DOC_CHUNK_OVERLAP = 120;

export function normalizeText(text: string): string {
  return text
    .replace(/\r\n/g, "\n")
    .replace(/\t/g, " ")
    .replace(/[ \u00a0]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export function chunkText(
  text: string,
  chunkSize = DOC_CHUNK_SIZE,
  overlap = DOC_CHUNK_OVERLAP
): string[] {
  const normalized = normalizeText(text);
  if (!normalized) return [];

  if (normalized.length <= chunkSize) {
    return [normalized];
  }

  const chunks: string[] = [];
  let start = 0;
  while (start < normalized.length) {
    let end = Math.min(start + chunkSize, normalized.length);
    if (end < normalized.length) {
      const slice = normalized.slice(start, end);
      const breakAt = Math.max(
        slice.lastIndexOf("\n\n"),
        slice.lastIndexOf(". "),
        slice.lastIndexOf(" ")
      );
      if (breakAt > chunkSize * 0.5) {
        end = start + breakAt + 1;
      }
    }
    const chunk = normalized.slice(start, end).trim();
    if (chunk) chunks.push(chunk);
    if (end >= normalized.length) break;
    start = Math.max(end - overlap, start + 1);
  }
  return chunks;
}

export function guessMimeFromFilename(filename: string): string {
  const ext = path.extname(filename).toLowerCase();
  switch (ext) {
    case ".txt":
      return "text/plain";
    case ".md":
    case ".markdown":
      return "text/markdown";
    case ".csv":
      return "text/csv";
    case ".json":
      return "application/json";
    case ".pdf":
      return "application/pdf";
    case ".docx":
      return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    case ".xlsx":
      return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".png":
      return "image/png";
    case ".webp":
      return "image/webp";
    default:
      return "application/octet-stream";
  }
}

export async function extractTextFromFile(
  filePath: string,
  mimeType: string,
  filename: string
): Promise<string> {
  const ext = path.extname(filename).toLowerCase();

  if (mimeType === "text/plain" || ext === ".txt") {
    return fs.readFileSync(filePath, "utf-8");
  }
  if (mimeType === "text/markdown" || ext === ".md" || ext === ".markdown") {
    return fs.readFileSync(filePath, "utf-8");
  }
  if (mimeType === "text/csv" || ext === ".csv") {
    return fs.readFileSync(filePath, "utf-8");
  }
  if (mimeType === "application/json" || ext === ".json") {
    const raw = fs.readFileSync(filePath, "utf-8");
    try {
      return JSON.stringify(JSON.parse(raw), null, 2);
    } catch {
      return raw;
    }
  }
  if (mimeType === "application/pdf" || ext === ".pdf") {
    const { PDFParse } = await import("pdf-parse");
    const buffer = fs.readFileSync(filePath);
    const parser = new PDFParse({ data: buffer });
    const result = await parser.getText();
    return result?.text ?? "";
  }
  if (
    mimeType ===
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ||
    ext === ".docx"
  ) {
    const mammoth = await import("mammoth");
    const result = await mammoth.extractRawText({ path: filePath });
    return result.value ?? "";
  }
  if (
    mimeType ===
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ||
    ext === ".xlsx"
  ) {
    const XLSX = await import("xlsx");
    const workbook = XLSX.read(fs.readFileSync(filePath), { type: "buffer" });
    const parts: string[] = [];
    for (const sheetName of workbook.SheetNames) {
      const sheet = workbook.Sheets[sheetName];
      parts.push(`# Sheet: ${sheetName}`);
      parts.push(XLSX.utils.sheet_to_csv(sheet));
    }
    return parts.join("\n\n");
  }

  throw new Error(`Extraction non supportée pour ${mimeType}`);
}
