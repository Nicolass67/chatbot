"use client";

import { useRef } from "react";
import { cn } from "@/lib/utils/cn";
import { fileKindLabel, fileTypeIcon } from "./file-icons";
import {
  formatBytes,
  formatMtime,
  type FilesEntry,
  type FilesSortDir,
  type FilesSortKey,
} from "./types";

interface FilesListViewProps {
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
  sort: FilesSortKey;
  sortDir: FilesSortDir;
  onSort: (key: FilesSortKey) => void;
}

function SortHeader({
  label,
  active,
  dir,
  onClick,
  className,
}: {
  label: string;
  active: boolean;
  dir: FilesSortDir;
  onClick: () => void;
  className?: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "truncate text-left text-xs font-medium uppercase tracking-wide text-muted hover:text-foreground",
        className
      )}
    >
      {label}
      {active ? (dir === "asc" ? " ↑" : " ↓") : ""}
    </button>
  );
}

export function FilesListView({
  entries,
  selectedIds,
  focusedId,
  onFocus,
  onOpen,
  onSelect,
  onContextMenu,
  onLongPressSelect,
  onDropOnFolder,
  sort,
  sortDir,
  onSort,
}: FilesListViewProps) {
  const longPressTimer = useRef<number | null>(null);
  const dragIds = useRef<string[]>([]);

  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden" role="grid" aria-multiselectable>
      <div className="hidden shrink-0 grid-cols-[minmax(0,1fr)_88px_88px_120px] gap-3 border-b border-border-subtle px-3 py-2 md:grid lg:px-4">
        <SortHeader label="Nom" active={sort === "name"} dir={sortDir} onClick={() => onSort("name")} />
        <SortHeader label="Type" active={sort === "type"} dir={sortDir} onClick={() => onSort("type")} />
        <SortHeader label="Taille" active={sort === "size"} dir={sortDir} onClick={() => onSort("size")} />
        <SortHeader label="Modifié" active={sort === "mtime"} dir={sortDir} onClick={() => onSort("mtime")} />
      </div>

      <ul className="min-h-0 flex-1 overflow-y-auto px-2 py-1 lg:px-3" role="rowgroup">
        {entries.map((entry) => {
          const Icon = fileTypeIcon(entry.name, entry.isDirectory);
          const selected = selectedIds.has(entry.fileId);
          const focused = focusedId === entry.fileId;
          return (
            <li key={entry.fileId} className="list-none" role="presentation">
              <div
                role="row"
                tabIndex={focused ? 0 : -1}
                aria-selected={selected}
                onFocus={() => onFocus(entry.fileId)}
                onClick={(e) => {
                  const additive = e.metaKey || e.ctrlKey;
                  const range = e.shiftKey;
                  // Dossier : un clic entre dedans (sauf multi-sélection).
                  if (entry.isDirectory && !additive && !range) {
                    onOpen(entry);
                    return;
                  }
                  const isTouch =
                    "ontouchstart" in window || navigator.maxTouchPoints > 0;
                  if (isTouch && window.matchMedia("(max-width: 1023px)").matches) {
                    if (selectedIds.size > 0 || additive || range) {
                      onSelect(entry, { additive: true, range });
                      return;
                    }
                    onOpen(entry);
                    return;
                  }
                  onSelect(entry, { additive, range });
                }}
                onDoubleClick={(e) => {
                  e.preventDefault();
                  onOpen(entry);
                }}
                onContextMenu={(e) => {
                  e.preventDefault();
                  onContextMenu?.(entry, e.clientX, e.clientY);
                }}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    e.preventDefault();
                    onOpen(entry);
                  }
                  if (e.key === " ") {
                    e.preventDefault();
                    onSelect(entry, { additive: true, range: false });
                  }
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
                  "mb-0.5 grid w-full cursor-default grid-cols-1 items-center gap-1 rounded-[var(--radius-md)] px-2 py-2.5 text-left transition-colors md:grid-cols-[minmax(0,1fr)_88px_88px_120px] md:gap-3 md:py-1.5",
                  selected
                    ? "bg-accent/15 text-foreground"
                    : "hover:bg-surface-hover",
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
                <span className="flex min-w-0 items-center gap-2.5" role="gridcell">
                  <Icon
                    className={cn(
                      "h-4 w-4 shrink-0",
                      entry.isDirectory ? "text-muted" : "text-muted-foreground"
                    )}
                  />
                  <span className="min-w-0">
                    <span className="flex min-w-0 items-center gap-1.5">
                      <span className="block truncate text-sm font-medium">
                        {entry.name}
                      </span>
                    </span>
                    <span className="block truncate text-xs text-muted md:hidden">
                      {entry.isDirectory
                        ? "Dossier"
                        : `${fileKindLabel(entry.name, false)} · ${formatBytes(entry.sizeBytes)}`}
                    </span>
                    {entry.snippet && (
                      <span className="mt-0.5 block truncate text-xs text-muted">
                        {entry.snippet}
                      </span>
                    )}
                  </span>
                  {entry.matchSource && (
                    <span className="ml-auto shrink-0 rounded bg-surface-elevated px-1.5 py-0.5 text-[10px] uppercase text-muted md:ml-2">
                      {entry.matchSource === "content" ? "Contenu" : "Nom"}
                    </span>
                  )}
                </span>
                <span className="hidden truncate text-xs text-muted md:block" role="gridcell">
                  {fileKindLabel(entry.name, entry.isDirectory)}
                </span>
                <span className="hidden truncate text-xs text-muted md:block" role="gridcell">
                  {entry.isDirectory ? "—" : formatBytes(entry.sizeBytes)}
                </span>
                <span className="hidden truncate text-xs text-muted md:block" role="gridcell">
                  {formatMtime(entry.mtimeMs)}
                </span>
              </div>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
