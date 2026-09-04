"use client";

import { useCallback, useEffect, useState } from "react";
import { ChevronRight, Folder, Home } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { Spinner } from "@/components/ui/Spinner";
import { IconButton } from "@/components/ui/IconButton";

export type FolderPickerRoot = { id: string; label: string };

type DirEntry = {
  fileId: string;
  name: string;
  relativePath: string;
  isDirectory: boolean;
};

interface FilesFolderPickerProps {
  roots: FolderPickerRoot[];
  rootId: string;
  path: string;
  onRootChange: (rootId: string) => void;
  onPathChange: (path: string) => void;
  className?: string;
}

export function FilesFolderPicker({
  roots,
  rootId,
  path,
  onRootChange,
  onPathChange,
  className,
}: FilesFolderPickerProps) {
  const [dirs, setDirs] = useState<DirEntry[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!rootId) return;
    setBusy(true);
    setError(null);
    try {
      const sp = new URLSearchParams({
        root: rootId,
        path,
        limit: "200",
      });
      const res = await fetch(`/api/files/list?${sp}`);
      const data = (await res.json()) as {
        entries?: DirEntry[];
        error?: string;
      };
      if (!res.ok) throw new Error(data.error ?? "Liste indisponible");
      setDirs((data.entries ?? []).filter((e) => e.isDirectory));
    } catch (err) {
      setDirs([]);
      setError(err instanceof Error ? err.message : "Erreur");
    } finally {
      setBusy(false);
    }
  }, [rootId, path]);

  useEffect(() => {
    void load();
  }, [load]);

  const segments = path ? path.split("/").filter(Boolean) : [];
  const rootLabel = roots.find((r) => r.id === rootId)?.label ?? "Source";

  return (
    <div className={cn("space-y-2", className)}>
      <label className="block text-sm">
        Source
        <select
          className="mt-1 w-full rounded-[var(--radius-md)] border border-border-subtle bg-background px-3 py-2 text-sm outline-none focus:border-border-strong"
          value={rootId}
          onChange={(e) => {
            onRootChange(e.target.value);
            onPathChange("");
          }}
        >
          {roots.map((r) => (
            <option key={r.id} value={r.id}>
              {r.label}
            </option>
          ))}
        </select>
      </label>

      <nav
        aria-label="Chemin destination"
        className="flex flex-wrap items-center gap-0.5 text-xs text-muted"
      >
        <button
          type="button"
          className="inline-flex items-center gap-1 rounded px-1.5 py-1 hover:bg-surface-hover hover:text-foreground"
          onClick={() => onPathChange("")}
        >
          <Home className="h-3 w-3" />
          {rootLabel}
        </button>
        {segments.map((seg, i) => {
          const partial = segments.slice(0, i + 1).join("/");
          return (
            <span key={partial} className="inline-flex items-center gap-0.5">
              <ChevronRight className="h-3 w-3 opacity-50" />
              <button
                type="button"
                className="rounded px-1.5 py-1 hover:bg-surface-hover hover:text-foreground"
                onClick={() => onPathChange(partial)}
              >
                {seg}
              </button>
            </span>
          );
        })}
      </nav>

      <div className="max-h-48 overflow-y-auto rounded-[var(--radius-md)] border border-border-subtle bg-background">
        {busy ? (
          <div className="flex items-center gap-2 px-3 py-4 text-xs text-muted">
            <Spinner size="sm" /> Chargement…
          </div>
        ) : error ? (
          <p className="px-3 py-3 text-sm text-error">{error}</p>
        ) : dirs.length === 0 ? (
          <p className="px-3 py-3 text-xs text-muted">
            Aucun sous-dossier — ce dossier sera la destination.
          </p>
        ) : (
          <ul className="divide-y divide-border-subtle">
            {dirs.map((d) => (
              <li key={d.fileId}>
                <button
                  type="button"
                  className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm hover:bg-surface-hover"
                  onClick={() => onPathChange(d.relativePath)}
                >
                  <Folder className="h-4 w-4 shrink-0 text-accent" />
                  <span className="min-w-0 flex-1 truncate">{d.name}</span>
                  <ChevronRight className="h-3.5 w-3.5 shrink-0 text-muted" />
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="flex items-center justify-between gap-2">
        <p className="min-w-0 truncate text-xs text-muted">
          Destination : {rootLabel}
          {path ? ` / ${path}` : " (racine)"}
        </p>
        {path ? (
          <IconButton
            size="sm"
            variant="ghost"
            label="Remonter"
            onClick={() => {
              const parent = path.includes("/")
                ? path.slice(0, path.lastIndexOf("/"))
                : "";
              onPathChange(parent);
            }}
          >
            <ChevronRight className="h-4 w-4 rotate-180" />
          </IconButton>
        ) : null}
      </div>
    </div>
  );
}
