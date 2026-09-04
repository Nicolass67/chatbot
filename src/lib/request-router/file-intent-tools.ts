import type { FileIntent } from "./types";

export const FILE_INTENT_TOOL_MAP: Record<
  Exclude<FileIntent, "none">,
  readonly string[]
> = {
  search: ["file_search"],
  list: ["file_list", "file_search"],
  read: ["file_stat", "file_read"],
  analyze: ["file_analyze", "file_read"],
  organize: ["file_search", "file_rename", "file_move", "file_create_directory"],
};

export function fileIntentToTools(intent: FileIntent): string[] {
  if (intent === "none") return [];
  return [...FILE_INTENT_TOOL_MAP[intent]];
}

export function resolveFileIntent(
  classification: { files?: { intent?: FileIntent } } | null | undefined
): FileIntent {
  return classification?.files?.intent ?? "none";
}
