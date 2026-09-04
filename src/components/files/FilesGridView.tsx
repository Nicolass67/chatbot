"use client";

import { useRef } from "react";
import { cn } from "@/lib/utils/cn";
import { fileTypeIcon } from "./file-icons";
import { formatBytes, type FilesEntry } from "./types";

interface FilesGridViewProps {
  entries: FilesEntry[];
  selectedIds: Set<string>;
  focusedId: string | null;
  onFocus: (id: string) => void;
  onOpen: (entry: FilesEntry) => void;
  onSelect: (
    entry: FilesEntry,
    opts: { additive: boolean; range: boolean }
  ) => void;
  onContextMenu?: (entry: FilesEntry, x: number, y: number) => void;
  onLongPressSelect?: (entry: FilesEntry) => void;
  onDropOnFolder?: (targetFolder: FilesEntry, draggedIds: string[]) => void;
}

export function FilesGridView({
  entries,
  selectedIds,
  focusedId,
  onFocus,
  onOpen,
  onSelect,
  onContextMenu,
  onLongPressSelect,
  onDropOnFolder,
}: FilesGridViewProps) {
  const longPressTimer = useRef<number | null>(null);
  const dragIds = useRef<string[]>([]);

  return (
    <div
      className="min-h-0 flex-1 overflow-y-auto p-3 lg:p-4"
      role="grid"
      aria-multiselectable
    >
      <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4 xl:grid-cols-5 2xl:grid-cols-6">
        {entries.map((entry) => {
          const Icon = fileTypeIcon(entry.name, entry.isDirectory);
          const selected = selectedIds.has(entry.fileId);
          const focused = focusedId === entry.fileId;
          return (
            <li key={entry.fileId} role="row">
              <button
                type="button"
                role="gridcell"
                tabIndex={focused ? 0 : -1}
                aria-selected={selected}
                title={entry.name}
                onFocus={() => onFocus(entry.fileId)}
                onClick={(e) => {
                  const additive = e.metaKey || e.ctrlKey;
                  const range = e.shiftKey;
                  // Dossier : un clic entre dedans (sauf multi-sélection).
                  if (entry.isDirectory && !additive && !range) {
                    onOpen(entry);
                    return;
                  }
                  const isNarrow = window.matchMedia("(max-width: 1023px)").matches;
                  if (isNarrow) {
                    if (selectedIds.size > 0 || additive || range) {
                      onSelect(entry, { additive: true, range });
                      return;
                    }
                    onOpen(entry);
                    return;
                  }
                  if (e.detail === 2) {
                    onOpen(entry);
                    return;
                  }
                  onSelect(entry, { additive, range });
                }}
                onDoubleClick={() => onOpen(entry)}
                onContextMenu={(e) => {
                  e.preventDefault();
                  onContextMenu?.(entry, e.clientX, e.clientY);
                }}
                onTouchStart={() => {
                  longPressTimer.current = window.setTimeout(() => {
                    onLongPressSelect?.(entry);
                  }, 450);
                }}
                onTouchEnd={() => {
                  if (longPressTimer.current) {
                    window.clearTimeout(longPressTimer.current);
                    longPressTimer.current = null;
                  }
                }}
                onTouchMove={() => {
                  if (longPressTimer.current) {
                    window.clearTimeout(longPressTimer.current);
                    longPressTimer.current = null;
                  }
                }}
                className={cn(
                  "flex h-full w-full flex-col items-center gap-2 rounded-[var(--radius-md)] px-2 py-3 text-center transition-colors hover:bg-surface-hover",
                  selected
                    ? "border-accent/40 bg-accent/15"
                    : "bg-surface hover:bg-surface-hover",
                  focused && "ring-1 ring-accent/50"
                )}
                draggable={!entry.isDirectory}
                onDragStart={(e) => {
                  const ids = selectedIds.has(entry.fileId)
                    ? [...selectedIds]
                    : [entry.fileId];
                  dragIds.current = ids;
                  e.dataTransfer.setData(
                    "application/x-files-ids",
                    JSON.stringify(ids)
                  );
                  e.dataTransfer.effectAllowed = "move";
                }}
                onDragOver={(e) => {
                  if (!entry.isDirectory || !onDropOnFolder) return;
                  e.preventDefault();
                  e.dataTransfer.dropEffect = "move";
                }}
                onDrop={(e) => {
                  if (!entry.isDirectory || !onDropOnFolder) return;
                  e.preventDefault();
                  let ids = dragIds.current;
                  try {
                    const raw = e.dataTransfer.getData("application/x-files-ids");
                    if (raw) ids = JSON.parse(raw) as string[];
                  } catch {
                    /* ignore */
                  }
                  if (ids.length) onDropOnFolder(entry, ids);
                }}
              >
                <Icon
                  className={cn(
                    "h-10 w-10",
                    entry.isDirectory ? "text-muted" : "text-muted-foreground"
                  )}
                />
                <span className="line-clamp-2 w-full break-all text-xs font-medium leading-snug">
                  {entry.name}
                </span>
                <span className="text-[10px] text-muted">
                  {entry.isDirectory
                    ? "Dossier"
                    : formatBytes(entry.sizeBytes)}
                </span>
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
