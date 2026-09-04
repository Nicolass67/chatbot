import {
  File,
  FileArchive,
  FileCode,
  FileImage,
  FileJson,
  FileSpreadsheet,
  FileText,
  Folder,
  type LucideIcon,
} from "lucide-react";
import { extensionOfName } from "./types";

export function fileTypeIcon(
  name: string,
  isDirectory: boolean
): LucideIcon {
  if (isDirectory) return Folder;
  const ext = extensionOfName(name);
  switch (ext) {
    case ".png":
    case ".jpg":
    case ".jpeg":
    case ".webp":
    case ".gif":
    case ".bmp":
    case ".svg":
      return FileImage;
    case ".pdf":
    case ".txt":
    case ".md":
    case ".markdown":
    case ".doc":
    case ".docx":
      return FileText;
    case ".json":
      return FileJson;
    case ".csv":
    case ".xlsx":
    case ".xls":
      return FileSpreadsheet;
    case ".js":
    case ".ts":
    case ".tsx":
    case ".jsx":
    case ".py":
    case ".rs":
    case ".go":
    case ".java":
    case ".c":
    case ".cpp":
    case ".h":
    case ".css":
    case ".html":
    case ".xml":
    case ".yml":
    case ".yaml":
    case ".toml":
    case ".sh":
    case ".ps1":
      return FileCode;
    case ".zip":
    case ".7z":
    case ".rar":
    case ".tar":
    case ".gz":
      return FileArchive;
    default:
      return File;
  }
}

export function fileKindLabel(name: string, isDirectory: boolean): string {
  if (isDirectory) return "Dossier";
  const ext = extensionOfName(name);
  if (!ext) return "Fichier";
  return ext.slice(1).toUpperCase();
}
