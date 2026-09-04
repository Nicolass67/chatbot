import { Loader2, Wrench } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface ToolStatusProps {
  tool?: string;
  status: "idle" | "running" | "done";
  summary?: string;
  sourceCount?: number;
  className?: string;
}

const TOOL_RUNNING_LABELS: Record<string, string> = {
  web_search: "Recherche sur le Web…",
  email_list: "Lecture des emails…",
  email_search: "Recherche d'emails…",
  email_get_thread: "Lecture du fil de discussion…",
  email_analyze: "Analyse des emails…",
  email_create_draft: "Rédaction du brouillon…",
};

export function ToolStatus({
  tool,
  status,
  summary,
  sourceCount,
  className,
}: ToolStatusProps) {
  if (status === "idle") return null;

  return (
    <div
      className={cn(
        "flex items-center gap-2.5 rounded-[var(--radius-lg)] border border-border-subtle bg-surface px-3.5 py-2.5 text-sm text-muted",
        className
      )}
      role="status"
      aria-live="polite"
    >
      {status === "running" ? (
        <>
          <Loader2 className="h-4 w-4 shrink-0 animate-spin text-accent" />
          <span>
            {tool
              ? (TOOL_RUNNING_LABELS[tool] ?? `Exécution de ${tool}…`)
              : "Exécution de l'outil…"}
          </span>
        </>
      ) : (
        <>
          <Wrench className="h-4 w-4 shrink-0 text-accent" />
          <span>
            {summary ?? "Outil terminé"}
            {sourceCount !== undefined && sourceCount > 0
              ? ` · ${sourceCount} source${sourceCount > 1 ? "s" : ""}`
              : ""}
          </span>
        </>
      )}
    </div>
  );
}
