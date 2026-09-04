"use client";

import { FolderOpen, Download, HardDrive } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import type { FilesRoot } from "./types";

interface FilesRootsNavProps {
  roots: FilesRoot[];
  activeRootId: string;
  onSelect: (rootId: string) => void;
  /** false tant que /api/files/roots n'a pas répondu — évite le faux « Aucune source ». */
  loaded?: boolean;
}

function rootIcon(label: string) {
  const l = label.toLowerCase();
  if (l.includes("download")) return Download;
  if (l.includes("document")) return FolderOpen;
  return HardDrive;
}

export function FilesRootsNav({
  roots,
  activeRootId,
  onSelect,
  loaded = true,
}: FilesRootsNavProps) {
  const enabled = roots.filter((r) => r.enabled);

  if (!loaded) {
    return (
      <div
        className="space-y-2 px-2"
        aria-busy="true"
        aria-label="Chargement des sources"
      >
        <div className="h-9 animate-pulse rounded-[var(--radius-md)] bg-border-subtle/60" />
        <div className="h-9 animate-pulse rounded-[var(--radius-md)] bg-border-subtle/40" />
      </div>
    );
  }

  if (enabled.length === 0) {
    return (
      <p className="px-2 text-sm text-muted">
        Aucune source activée. Configurez-les dans les paramètres.
      </p>
    );
  }

  return (
    <ul className="space-y-1">
      {enabled.map((root) => {
        const Icon = rootIcon(root.label);
        const active = root.id === activeRootId;
        return (
          <li key={root.id}>
            <button
              type="button"
              onClick={() => onSelect(root.id)}
              className={cn(
                "flex w-full items-center gap-2 rounded-[var(--radius-md)] px-3 py-2.5 text-left text-sm transition-colors",
                active
                  ? "bg-surface-hover font-medium text-foreground"
                  : "text-muted hover:bg-surface-hover hover:text-foreground"
              )}
            >
              <Icon className="h-4 w-4 shrink-0" />
              <span className="truncate">{root.label}</span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}
