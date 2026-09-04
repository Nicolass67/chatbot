"use client";

import { Check, Globe, Loader2, Search } from "lucide-react";
import { cn } from "@/lib/utils/cn";

export type WebSearchPhase = "idle" | "searching" | "analyzing" | "done";

interface WebSearchActivityProps {
  phase: WebSearchPhase;
  query?: string;
  sourceCount?: number;
  className?: string;
}

export function WebSearchActivity({
  phase,
  query,
  sourceCount,
  className,
}: WebSearchActivityProps) {
  if (phase === "idle") return null;

  const isActive = phase === "searching" || phase === "analyzing";

  return (
    <div
      className={cn(
        "flex items-start gap-2.5 py-1",
        className
      )}
      role="status"
      aria-live="polite"
    >
      <div
        className={cn(
          "mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center",
          isActive ? "text-muted" : "text-success"
        )}
      >
        {phase === "done" ? (
          <Check className="h-4 w-4" />
        ) : phase === "analyzing" ? (
          <Loader2 className="h-4 w-4 animate-spin" />
        ) : (
          <Globe className="h-4 w-4" />
        )}
      </div>

      <div className="min-w-0 flex-1 space-y-1">
        <div className="flex flex-wrap items-center gap-2">
          <Search className="h-3.5 w-3.5 text-muted-foreground" />
          <span className="text-sm font-medium text-foreground">
            {phase === "searching" && "Recherche sur le Web…"}
            {phase === "analyzing" && "Analyse des résultats…"}
            {phase === "done" &&
              `${sourceCount ?? 0} source${(sourceCount ?? 0) > 1 ? "s" : ""} trouvée${(sourceCount ?? 0) > 1 ? "s" : ""}`}
          </span>
        </div>

        {query && (
          <p className="truncate text-xs text-muted">
            Requête · « {query} »
          </p>
        )}

        {phase === "done" && (sourceCount ?? 0) > 0 && (
          <p className="text-xs text-muted-foreground">
            Les sources apparaissent dans la réponse ci-dessus.
          </p>
        )}
      </div>
    </div>
  );
}
