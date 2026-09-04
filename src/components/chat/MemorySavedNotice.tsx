"use client";

import { useState } from "react";
import { Brain, X } from "lucide-react";
import {
  memoryCategoryLabel,
  type SavedMemoryItem,
} from "@/lib/memory/saved-memory";
import { cn } from "@/lib/utils/cn";

interface MemorySavedNoticeProps {
  memories: SavedMemoryItem[];
  onDelete: (memoryId: string) => Promise<void>;
  className?: string;
}

function truncateContent(content: string, max = 72): string {
  const trimmed = content.trim();
  if (trimmed.length <= max) return trimmed;
  return `${trimmed.slice(0, max - 1)}…`;
}

export function MemorySavedNotice({
  memories,
  onDelete,
  className,
}: MemorySavedNoticeProps) {
  const [confirmingId, setConfirmingId] = useState<string | null>(null);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  if (memories.length === 0) return null;

  const handleDelete = async (memoryId: string) => {
    setDeletingId(memoryId);
    try {
      await onDelete(memoryId);
      setConfirmingId(null);
    } finally {
      setDeletingId(null);
    }
  };

  return (
    <div className={cn("mb-3 space-y-2", className)}>
      {memories.map((memory) => {
        const isConfirming = confirmingId === memory.id;
        const isDeleting = deletingId === memory.id;

        return (
          <div key={memory.id} className="max-w-full">
            {!isConfirming ? (
              <button
                type="button"
                onClick={() => setConfirmingId(memory.id)}
                className="group inline-flex max-w-full items-center gap-2 rounded-lg border border-border/60 bg-surface/50 px-3 py-2 text-left transition-colors hover:border-accent/30 hover:bg-surface"
                title={memory.content}
              >
                <Brain className="h-3.5 w-3.5 shrink-0 text-accent" />
                <span className="min-w-0 text-xs leading-snug text-muted-foreground">
                  <span className="font-medium text-foreground">Mémorisé</span>
                  <span className="text-muted"> · </span>
                  <span className="text-muted-foreground">
                    {memoryCategoryLabel(memory.category)}
                  </span>
                  <span className="text-muted"> · </span>
                  <span className="text-foreground/90">
                    {truncateContent(memory.content)}
                  </span>
                </span>
              </button>
            ) : (
              <div className="rounded-lg border border-border/70 bg-surface/70 px-3 py-2.5">
                <p className="text-xs leading-relaxed text-foreground">
                  Supprimer cette information de la mémoire ?
                </p>
                <p className="mt-1 line-clamp-2 text-[11px] text-muted-foreground">
                  {memory.content}
                </p>
                <div className="mt-2.5 flex flex-wrap gap-2">
                  <button
                    type="button"
                    disabled={isDeleting}
                    onClick={() => void handleDelete(memory.id)}
                    className="inline-flex items-center gap-1 rounded-md bg-error/10 px-2.5 py-1 text-[11px] font-medium text-error transition-colors hover:bg-error/15 disabled:opacity-60"
                  >
                    <X className="h-3 w-3" />
                    {isDeleting ? "Suppression…" : "Supprimer"}
                  </button>
                  <button
                    type="button"
                    disabled={isDeleting}
                    onClick={() => setConfirmingId(null)}
                    className="rounded-md px-2.5 py-1 text-[11px] font-medium text-muted-foreground transition-colors hover:bg-surface-hover hover:text-foreground disabled:opacity-60"
                  >
                    Garder
                  </button>
                </div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
