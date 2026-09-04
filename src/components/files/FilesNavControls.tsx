"use client";

import {
  ArrowLeft,
  ArrowRight,
  ArrowUp,
  ChevronRight,
  RefreshCw,
} from "lucide-react";
import { IconButton } from "@/components/ui/IconButton";
import { cn } from "@/lib/utils/cn";
import { pathSegments } from "./types";

interface FilesNavControlsProps {
  canGoBack: boolean;
  canGoForward: boolean;
  atRoot: boolean;
  refreshing?: boolean;
  onBack: () => void;
  onForward: () => void;
  onParent: () => void;
  onRefresh: () => void;
}

export function FilesNavControls({
  canGoBack,
  canGoForward,
  atRoot,
  refreshing,
  onBack,
  onForward,
  onParent,
  onRefresh,
}: FilesNavControlsProps) {
  return (
    <div className="flex items-center gap-0.5">
      <IconButton
        label="Précédent"
        size="sm"
        disabled={!canGoBack}
        onClick={onBack}
      >
        <ArrowLeft className="h-4 w-4" />
      </IconButton>
      <IconButton
        label="Suivant"
        size="sm"
        className="hidden sm:inline-flex"
        disabled={!canGoForward}
        onClick={onForward}
      >
        <ArrowRight className="h-4 w-4" />
      </IconButton>
      <IconButton
        label="Dossier parent"
        size="sm"
        disabled={atRoot}
        onClick={onParent}
      >
        <ArrowUp className="h-4 w-4" />
      </IconButton>
      <IconButton
        label="Actualiser"
        size="sm"
        disabled={refreshing}
        onClick={onRefresh}
      >
        <RefreshCw className={cn("h-4 w-4", refreshing && "animate-spin")} />
      </IconButton>
    </div>
  );
}

interface FilesBreadcrumbsProps {
  rootLabel: string;
  path: string;
  onNavigateRoot: () => void;
  onNavigateSegment: (path: string) => void;
}

export function FilesBreadcrumbs({
  rootLabel,
  path,
  onNavigateRoot,
  onNavigateSegment,
}: FilesBreadcrumbsProps) {
  const segments = pathSegments(path);
  const collapsed =
    segments.length > 3
      ? {
          head: segments.slice(0, 0),
          midHidden: true,
          tail: segments.slice(-2),
          tailStart: segments.length - 2,
        }
      : {
          head: segments,
          midHidden: false,
          tail: [] as string[],
          tailStart: 0,
        };

  const renderCrumb = (label: string, onClick?: () => void, current?: boolean) => (
    <button
      type="button"
      disabled={current || !onClick}
      onClick={onClick}
      className={cn(
        "max-w-[5rem] truncate rounded px-1 py-0.5 text-sm transition-colors sm:max-w-[9rem]",
        current
          ? "font-medium text-foreground"
          : "text-muted hover:bg-surface-hover hover:text-foreground"
      )}
      aria-current={current ? "page" : undefined}
    >
      {label}
    </button>
  );

  return (
    <nav aria-label="Fil d'Ariane" className="min-w-0 flex-1">
      <ol className="flex min-w-0 items-center gap-0.5 overflow-hidden">
        <li className="flex min-w-0 items-center gap-0.5">
          {renderCrumb(rootLabel, segments.length === 0 ? undefined : onNavigateRoot, segments.length === 0)}
        </li>
        {collapsed.midHidden && (
          <li className="flex items-center gap-0.5 text-muted">
            <ChevronRight className="h-3.5 w-3.5 shrink-0 opacity-60" />
            <span className="px-1 text-sm">…</span>
          </li>
        )}
        {(collapsed.midHidden ? collapsed.tail : collapsed.head).map((seg, i) => {
          const absoluteIndex = collapsed.midHidden
            ? collapsed.tailStart + i
            : i;
          const crumbPath = segments.slice(0, absoluteIndex + 1).join("/");
          const isLast = absoluteIndex === segments.length - 1;
          return (
            <li key={crumbPath} className="flex min-w-0 items-center gap-0.5">
              <ChevronRight className="h-3.5 w-3.5 shrink-0 text-muted opacity-60" />
              {renderCrumb(
                seg,
                isLast ? undefined : () => onNavigateSegment(crumbPath),
                isLast
              )}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}
