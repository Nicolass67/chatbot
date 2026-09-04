"use client";

import { Button } from "@/components/ui/Button";
import { cn } from "@/lib/utils/cn";

interface FilesSelectionBarProps {
  count: number;
  onClear: () => void;
  onAnalyze?: () => void;
  onRename?: () => void;
  onMove?: () => void;
  onInfo?: () => void;
  className?: string;
}

export function FilesSelectionBar({
  count,
  onClear,
  onAnalyze,
  onRename,
  onMove,
  onInfo,
  className,
}: FilesSelectionBarProps) {
  if (count === 0) return null;

  return (
    <div
      className={cn(
        "flex flex-wrap items-center gap-2 border-b border-border-subtle bg-surface-elevated px-3 py-2 lg:px-4",
        className
      )}
    >
      <span className="text-sm font-medium">
        {count} élément{count > 1 ? "s" : ""} sélectionné{count > 1 ? "s" : ""}
      </span>
      <div className="ml-auto flex flex-wrap items-center gap-1.5">
        {onAnalyze && (
          <Button type="button" size="sm" variant="primary" onClick={onAnalyze}>
            Analyser
          </Button>
        )}
        {onRename && (
          <Button type="button" size="sm" variant="secondary" onClick={onRename}>
            Renommer
          </Button>
        )}
        {onMove && (
          <Button type="button" size="sm" variant="secondary" onClick={onMove}>
            Déplacer
          </Button>
        )}
        {onInfo && (
          <Button type="button" size="sm" variant="ghost" onClick={onInfo}>
            Infos
          </Button>
        )}
        <Button type="button" size="sm" variant="ghost" onClick={onClear}>
          Désélectionner
        </Button>
      </div>
    </div>
  );
}
