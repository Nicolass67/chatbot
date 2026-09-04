"use client";

import { useEffect } from "react";
import { createPortal } from "react-dom";
import {
  Eye,
  FolderOpen,
  Info,
  Move,
  Pencil,
  ScanSearch,
  X,
} from "lucide-react";
import { cn } from "@/lib/utils/cn";
import type { FilesEntry } from "./types";
import type { FilesContextAction } from "./FilesContextMenu";

interface FilesMobileActionsProps {
  entry: FilesEntry | null;
  onClose: () => void;
  onAction: (action: FilesContextAction, entry: FilesEntry) => void;
}

export function FilesMobileActions({
  entry,
  onClose,
  onAction,
}: FilesMobileActionsProps) {
  useEffect(() => {
    if (!entry) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prev;
      window.removeEventListener("keydown", onKey);
    };
  }, [entry, onClose]);

  if (!entry || typeof document === "undefined") return null;

  const actions: Array<{
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
    { id: "move", label: "Déplacer", icon: Move },
    { id: "info", label: "Informations", icon: Info },
  ];

  return createPortal(
    <div className="fixed inset-0 z-[var(--z-fab)] flex items-end justify-center sm:items-center sm:p-4">
      <button
        type="button"
        className="absolute inset-0 bg-black/50 backdrop-blur-[2px]"
        aria-label="Fermer"
        onClick={onClose}
      />
      <div
        role="dialog"
        aria-modal="true"
        aria-label={`Actions pour ${entry.name}`}
        className={cn(
          "glass-thick relative z-10 w-full max-w-md rounded-t-[var(--radius-2xl)] sm:rounded-[var(--radius-2xl)]",
          "safe-bottom"
        )}
      >
        <div className="mx-auto mt-2 h-1 w-10 rounded-full bg-border-strong/70 sm:hidden" aria-hidden />
        <div className="flex items-center justify-between px-4 py-3">
          <div className="min-w-0">
            <p className="truncate text-sm font-medium">{entry.name}</p>
            <p className="text-xs text-muted">
              {entry.isDirectory ? "Dossier" : "Fichier"}
            </p>
          </div>
          <button
            type="button"
            className="inline-flex h-11 w-11 items-center justify-center rounded-[var(--radius-md)] text-muted hover:bg-surface-hover hover:text-foreground"
            aria-label="Fermer"
            onClick={onClose}
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <ul className="max-h-[60dvh] overflow-y-auto p-2 pb-[max(0.5rem,env(safe-area-inset-bottom))]">
          {actions
            .filter((a) => !a.hidden)
            .map((action) => {
              const Icon = action.icon;
              return (
                <li key={action.id}>
                  <button
                    type="button"
                    className="flex min-h-11 w-full items-center gap-3 rounded-[var(--radius-md)] px-3 py-2.5 text-left text-sm hover:bg-surface-hover"
                    onClick={() => {
                      onAction(action.id, entry);
                      onClose();
                    }}
                  >
                    <Icon className="h-4 w-4 text-muted" />
                    {action.label}
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
