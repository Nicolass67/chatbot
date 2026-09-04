"use client";

import { useEffect, useMemo, useState } from "react";
import { createPortal } from "react-dom";
import {
  FolderPlus,
  LayoutGrid,
  List,
  RefreshCw,
  Search,
  Settings,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";

export type FilesCommand =
  | "search-focus"
  | "create-folder"
  | "go-documents"
  | "go-downloads"
  | "view-list"
  | "view-grid"
  | "refresh"
  | "settings"
  | "sort-name"
  | "sort-mtime";

interface FilesCommandPaletteProps {
  open: boolean;
  onClose: () => void;
  onCommand: (command: FilesCommand) => void;
  rootLabels: { documents?: string; downloads?: string };
}

const COMMANDS: Array<{
  id: FilesCommand;
  label: string;
  hint?: string;
  icon: typeof Search;
}> = [
  { id: "search-focus", label: "Rechercher", hint: "/", icon: Search },
  { id: "create-folder", label: "Nouveau dossier", hint: "Ctrl+Shift+N", icon: FolderPlus },
  { id: "go-documents", label: "Aller à Documents", icon: List },
  { id: "go-downloads", label: "Aller à Downloads", icon: List },
  { id: "view-list", label: "Vue liste", icon: List },
  { id: "view-grid", label: "Vue grille", icon: LayoutGrid },
  { id: "sort-name", label: "Trier par nom", icon: List },
  { id: "sort-mtime", label: "Trier par date", icon: List },
  { id: "refresh", label: "Actualiser", icon: RefreshCw },
  { id: "settings", label: "Paramètres Files", icon: Settings },
];

export function FilesCommandPalette({
  open,
  onClose,
  onCommand,
  rootLabels,
}: FilesCommandPaletteProps) {
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return COMMANDS.filter((c) => {
      if (c.id === "go-documents" && !rootLabels.documents) return false;
      if (c.id === "go-downloads" && !rootLabels.downloads) return false;
      if (!q) return true;
      return c.label.toLowerCase().includes(q);
    });
  }, [query, rootLabels]);

  useEffect(() => {
    if (!open) return;
    setQuery("");
    setActive(0);
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
      if (e.key === "ArrowDown") {
        e.preventDefault();
        setActive((i) => Math.min(filtered.length - 1, i + 1));
      }
      if (e.key === "ArrowUp") {
        e.preventDefault();
        setActive((i) => Math.max(0, i - 1));
      }
      if (e.key === "Enter") {
        e.preventDefault();
        const cmd = filtered[active];
        if (cmd) {
          onCommand(cmd.id);
          onClose();
        }
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, filtered, active, onClose, onCommand]);

  if (!open || typeof document === "undefined") return null;

  return createPortal(
    <div className="fixed inset-0 z-[130] flex items-start justify-center bg-black/50 p-4 pt-[12vh]">
      <button
        type="button"
        className="absolute inset-0"
        aria-label="Fermer la palette"
        onClick={onClose}
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Palette de commandes Files"
        className="relative z-10 w-full max-w-lg overflow-hidden rounded-[var(--radius-xl)] border border-border-subtle bg-surface shadow-xl"
      >
        <div className="flex items-center gap-2 border-b border-border-subtle px-3">
          <Search className="h-4 w-4 text-muted" />
          <input
            autoFocus
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setActive(0);
            }}
            placeholder="Commande Files…"
            className="h-11 w-full bg-transparent text-sm outline-none"
          />
        </div>
        <ul className="max-h-72 overflow-y-auto p-1">
          {filtered.length === 0 && (
            <li className="px-3 py-6 text-center text-sm text-muted">
              Aucune commande
            </li>
          )}
          {filtered.map((cmd, i) => {
            const Icon = cmd.icon;
            return (
              <li key={cmd.id}>
                <button
                  type="button"
                  className={cn(
                    "flex w-full items-center gap-2 rounded-[var(--radius-md)] px-3 py-2 text-left text-sm",
                    i === active ? "bg-surface-hover" : "hover:bg-surface-hover"
                  )}
                  onMouseEnter={() => setActive(i)}
                  onClick={() => {
                    onCommand(cmd.id);
                    onClose();
                  }}
                >
                  <Icon className="h-4 w-4 text-muted" />
                  <span className="flex-1">{cmd.label}</span>
                  {cmd.hint && (
                    <kbd className="text-[10px] text-muted">{cmd.hint}</kbd>
                  )}
                </button>
              </li>
            );
          })}
        </ul>
      </div>
    </div>,
    document.body
  );
}
