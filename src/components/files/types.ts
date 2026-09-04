export type FilesRoot = {
  id: string;
  label: string;
  absolutePath: string;
  enabled: boolean;
};

export type FilesEntry = {
  fileId: string;
  name: string;
  relativePath: string;
  isDirectory: boolean;
  sizeBytes: number;
  mtimeMs: number;
  extension?: string;
  indexed?: boolean;
  matchSource?: "name" | "content";
  snippet?: string;
};

export type FilesViewMode = "list" | "grid";
export type FilesSortKey = "name" | "mtime" | "size" | "type";
export type FilesSortDir = "asc" | "desc";
export type FilesSearchMode = "name" | "content" | "all";
export type FilesTypeFilter =
  | "all"
  | "folders"
  | "images"
  | "pdf"
  | "documents"
  | "indexed";

const IMAGE_EXTS = new Set([
  ".png",
  ".jpg",
  ".jpeg",
  ".webp",
  ".gif",
  ".bmp",
  ".svg",
]);
const DOC_EXTS = new Set([
  ".txt",
  ".md",
  ".markdown",
  ".doc",
  ".docx",
  ".rtf",
  ".odt",
  ".csv",
  ".xlsx",
  ".xls",
  ".json",
]);

export function entryMatchesTypeFilter(
  entry: FilesEntry,
  filter: FilesTypeFilter
): boolean {
  if (filter === "all") return true;
  if (filter === "folders") return entry.isDirectory;
  if (filter === "indexed") return Boolean(entry.indexed) && !entry.isDirectory;
  if (entry.isDirectory) return false;
  const ext = extensionOfName(entry.name);
  if (filter === "images") return IMAGE_EXTS.has(ext);
  if (filter === "pdf") return ext === ".pdf";
  if (filter === "documents") return DOC_EXTS.has(ext) || ext === ".pdf";
  return true;
}

export type FilesLocation = {
  rootId: string;
  path: string;
};

export function parentPath(path: string): string {
  const parts = path.split("/").filter(Boolean);
  if (parts.length === 0) return "";
  return parts.slice(0, -1).join("/");
}

export function pathSegments(path: string): string[] {
  return path.split("/").filter(Boolean);
}

export function extensionOfName(name: string): string {
  const i = name.lastIndexOf(".");
  if (i <= 0) return "";
  return name.slice(i).toLowerCase();
}

export function formatBytes(n: number): string {
  if (!Number.isFinite(n) || n < 0) return "—";
  if (n < 1024) return `${n} o`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(n < 10_240 ? 1 : 0)} Ko`;
  if (n < 1024 * 1024 * 1024)
    return `${(n / (1024 * 1024)).toFixed(n < 10_485_760 ? 1 : 0)} Mo`;
  return `${(n / (1024 * 1024 * 1024)).toFixed(1)} Go`;
}

export function formatMtime(ms: number): string {
  if (!ms) return "—";
  try {
    return new Intl.DateTimeFormat("fr-FR", {
      dateStyle: "short",
      timeStyle: "short",
    }).format(new Date(ms));
  } catch {
    return "—";
  }
}

export function sortEntries(
  entries: FilesEntry[],
  key: FilesSortKey,
  dir: FilesSortDir
): FilesEntry[] {
  const mul = dir === "asc" ? 1 : -1;
  return [...entries].sort((a, b) => {
    if (a.isDirectory !== b.isDirectory) return a.isDirectory ? -1 : 1;
    let cmp = 0;
    switch (key) {
      case "mtime":
        cmp = a.mtimeMs - b.mtimeMs;
        break;
      case "size":
        cmp = a.sizeBytes - b.sizeBytes;
        break;
      case "type": {
        const ea = a.isDirectory ? "" : extensionOfName(a.name);
        const eb = b.isDirectory ? "" : extensionOfName(b.name);
        cmp = ea.localeCompare(eb, "fr", { sensitivity: "base" });
        break;
      }
      default:
        cmp = a.name.localeCompare(b.name, "fr", {
          sensitivity: "base",
          numeric: true,
        });
    }
    if (cmp === 0) {
      cmp = a.name.localeCompare(b.name, "fr", {
        sensitivity: "base",
        numeric: true,
      });
    }
    return cmp * mul;
  });
}
