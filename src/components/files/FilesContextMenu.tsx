"use client";

import { useEffect, useRef } from "react";
import { createPortal } from "react-dom";
import {
  Eye,
  FolderOpen,
  Info,
  Move,
  Pencil,
  ScanSearch,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import type { FilesEntry } from "./types";

export type FilesContextAction =
  | "open"
  | "preview"
  | "analyze"
  | "rename"
  | "move"
  | "info";

interface FilesContextMenuProps {
  entry: FilesEntry | null;
  x: number;
  y: number;
  onAction: (action: FilesContextAction, entry: FilesEntry) => void;
  onClose: () => void;
}

export function FilesContextMenu({
  entry,
  x,
  y,
  onAction,
  onClose,
}: FilesContextMenuProps) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!entry) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) onClose();
    };
    window.addEventListener("keydown", onKey);
    window.addEventListener("mousedown", onDown);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.removeEventListener("mousedown", onDown);
    };
  }, [entry, onClose]);

  if (!entry || typeof document === "undefined") return null;

  const items: Array<{
    id: FilesContextAction;
    label: string;
    icon: typeof Eye;
    hidden?: boolean;
  }> = [
    {
      id: "open",
      label: entry.isDirectory ? "Ouvrir" : "Ouvrir / Aperçu",
      icon: entry.isDirectory ? FolderOpen : Eye,
    },
    {
      id: "preview",
      label: "Aperçu",
      icon: Eye,
      hidden: entry.isDirectory,
    },
    { id: "analyze", label: "Analyser avec l'IA", icon: ScanSearch },
    { id: "rename", label: "Renommer", icon: Pencil },
    { id: "move", label: "Déplacer…", icon: Move },
    { id: "info", label: "Informations", icon: Info },
  ];

  const left = Math.min(x, window.innerWidth - 220);
  const top = Math.min(y, window.innerHeight - 280);

  return createPortal(
    <div
      ref={ref}
      role="menu"
      aria-label={`Actions pour ${entry.name}`}
      className="fixed z-[120] min-w-[200px] overflow-hidden rounded-[var(--radius-lg)] border border-border-subtle bg-surface-elevated py-1 shadow-xl"
      style={{ left, top }}
    >
      <p className="truncate border-b border-border-subtle px-3 py-1.5 text-xs text-muted">
        {entry.name}
      </p>
      {items
        .filter((i) => !i.hidden)
        .map((item) => {
          const Icon = item.icon;
          return (
            <button
              key={item.id}
              type="button"
              role="menuitem"
              className={cn(
                "flex w-full items-center gap-2 px-3 py-2 text-left text-sm text-foreground hover:bg-surface-hover"
              )}
              onClick={() => {
                onAction(item.id, entry);
                onClose();
              }}
            >
              <Icon className="h-4 w-4 text-muted" />
              {item.label}
            </button>
          );
        })}
    </div>,
    document.body
  );
}
