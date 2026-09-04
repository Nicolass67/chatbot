"use client";

import { memo, useCallback, useEffect, useState } from "react";
import { ChevronDown, ChevronRight, Search } from "lucide-react";
import type { StepAction } from "@/lib/agent/types";
import type { AgentStepUiStatus, AgentUiPlan } from "@/components/chat/agent-ui-state";
import { cn } from "@/lib/utils/cn";

interface AgentPlanPanelProps {
  plan: AgentUiPlan | null;
  className?: string;
}

function stepStatusClass(status: AgentStepUiStatus): string {
  switch (status) {
    case "completed":
      return "text-success";
    case "failed":
    case "error":
      return "text-error";
    case "skipped":
      return "text-muted-foreground";
    case "running":
      return "text-accent";
    default:
      return "text-muted-foreground";
  }
}

function formatWebSearchQuery(action: StepAction): string | null {
  if (
    typeof action.input === "object" &&
    action.input !== null &&
    "query" in action.input
  ) {
    return String((action.input as { query: string }).query);
  }
  return null;
}

interface AgentStepRowProps {
  step: AgentUiPlan["steps"][number];
  expanded: boolean;
  onToggle: (stepId: string) => void;
}

const AgentStepRow = memo(function AgentStepRow({
  step,
  expanded,
  onToggle,
}: AgentStepRowProps) {
  const hasActions = step.actions.length > 0;
  const isRunning = step.status === "running";

  return (
    <li className="min-h-[36px]">
      <button
        type="button"
        onClick={() => hasActions && onToggle(step.id)}
        className={cn(
          "flex w-full items-center gap-2 rounded-[var(--radius-lg)] px-2 py-1.5 text-left transition-colors duration-[var(--duration-fast)]",
          hasActions && "cursor-pointer hover:bg-surface-hover",
          !hasActions && "cursor-default",
          isRunning && "bg-accent-subtle"
        )}
      >
        {hasActions ? (
          expanded ? (
            <ChevronDown className="h-3.5 w-3.5 shrink-0 text-muted" />
          ) : (
            <ChevronRight className="h-3.5 w-3.5 shrink-0 text-muted" />
          )
        ) : (
          <span className="w-3.5 shrink-0" aria-hidden />
        )}

        <span
          className={cn(
            "flex w-4 shrink-0 items-center justify-center",
            stepStatusClass(step.status)
          )}
          aria-hidden
        >
          {isRunning ? (
            <span className="pulse-dot" />
          ) : step.status === "completed" ? (
            "✓"
          ) : step.status === "failed" || step.status === "error" ? (
            "✕"
          ) : (
            "·"
          )}
        </span>

        <span
          className={cn(
            "flex-1 text-left text-sm",
            step.status === "completed" && "text-muted",
            step.status === "skipped" && "text-muted-foreground line-through",
            step.status === "failed" && "text-error",
            isRunning && "font-medium text-foreground"
          )}
        >
          {step.title}
        </span>
      </button>

      {expanded && hasActions && (
        <ul className="ml-7 mt-1 space-y-1 border-l border-border-subtle pl-3">
          {step.actions.map((action) => (
            <AgentActionRow key={action.id} action={action} />
          ))}
        </ul>
      )}
    </li>
  );
});

const AgentActionRow = memo(function AgentActionRow({
  action,
}: {
  action: StepAction;
}) {
  const query = formatWebSearchQuery(action);
  const provider = action.webSearchProvider ?? "Web Search";

  return (
    <li className="rounded-[var(--radius-md)] bg-surface px-2.5 py-2 text-xs">
      <div className="flex items-center gap-1.5 font-medium text-foreground">
        <Search className="h-3 w-3 text-accent" />
        {action.tool === "web_search" ? "Recherche Web" : action.tool}
      </div>
      {action.tool === "web_search" && (
        <p className="mt-1 text-muted">
          {action.status === "running" ? (
            <>
              <span className="text-accent">●</span> {provider}
              {query ? <> · « {query} »</> : null}
            </>
          ) : action.status === "error" ? (
            <>
              <span className="text-error">✕</span> {provider} indisponible
              {query ? <> · « {query} »</> : null}
            </>
          ) : action.webSearchStatus === "no_results" ? (
            <>
              <span className="text-warning">○</span> {provider}
              {query ? <> · « {query} »</> : null}
              {" — aucune source"}
            </>
          ) : (
            <>
              <span className="text-success">✓</span> {provider}
              {query ? <> · « {query} »</> : null}
            </>
          )}
        </p>
      )}
      {action.status === "done" &&
        action.sourceCount !== undefined &&
        action.webSearchStatus !== "no_results" && (
          <p className="mt-0.5 text-success">
            {action.sourceCount} source{action.sourceCount > 1 ? "s" : ""} trouvée
            {action.sourceCount > 1 ? "s" : ""}
          </p>
        )}
      {action.status === "error" && action.tool !== "web_search" && (
        <p className="mt-0.5 text-error">{action.error ?? "Erreur"}</p>
      )}
    </li>
  );
});

export const AgentPlanPanel = memo(function AgentPlanPanel({
  plan,
  className,
}: AgentPlanPanelProps) {
  const [expandedSteps, setExpandedSteps] = useState<Set<string>>(new Set());
  const [userToggled, setUserToggled] = useState(false);

  const toggleStep = useCallback((stepId: string) => {
    setUserToggled(true);
    setExpandedSteps((prev) => {
      const next = new Set(prev);
      if (next.has(stepId)) next.delete(stepId);
      else next.add(stepId);
      return next;
    });
  }, []);

  // Auto-expand running step unless user manually toggled
  useEffect(() => {
    if (!plan || userToggled) return;
    const running = plan.steps.find((s) => s.status === "running");
    if (running) {
      setExpandedSteps((prev) => new Set(prev).add(running.id));
    }
  }, [plan, userToggled]);

  if (!plan || plan.steps.length === 0) return null;

  return (
    <div
      className={cn(
        "rounded-[var(--radius-lg)] border border-border-subtle bg-transparent p-3 text-sm",
        className
      )}
    >
      <p className="mb-2.5 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
        Plan d&apos;exécution
      </p>
      <ul className="space-y-0.5">
        {plan.steps.map((step) => (
          <AgentStepRow
            key={step.id}
            step={step}
            expanded={expandedSteps.has(step.id)}
            onToggle={toggleStep}
          />
        ))}
      </ul>
    </div>
  );
});
