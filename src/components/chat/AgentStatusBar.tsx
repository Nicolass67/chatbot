"use client";

import { memo } from "react";
import { Loader2 } from "lucide-react";
import type { AgentPhase } from "@/lib/agent/types";
import { Badge } from "@/components/ui/Badge";
import { cn } from "@/lib/utils/cn";

interface AgentStatusBarProps {
  phase: AgentPhase;
  stepIndex?: number;
  totalSteps?: number;
  currentStepTitle?: string;
  className?: string;
}

export const AgentStatusBar = memo(function AgentStatusBar({
  phase,
  stepIndex,
  totalSteps,
  currentStepTitle,
  className,
}: AgentStatusBarProps) {
  const phaseLabel =
    phase === "planning"
      ? "Planification"
      : phase === "executing"
        ? "Exécution"
        : "Synthèse";

  const progress =
    phase === "executing" &&
    totalSteps !== undefined &&
    stepIndex !== undefined &&
    totalSteps > 0
      ? Math.round(((stepIndex + 1) / totalSteps) * 100)
      : null;

  return (
    <div
      className={cn(
        "border-l-2 border-border-strong py-1 pl-3",
        className
      )}
      role="status"
      aria-live="polite"
    >
      <div className="flex min-h-[24px] items-center gap-2.5">
        <Loader2 className="h-3.5 w-3.5 shrink-0 animate-spin text-muted" />
        <span className="text-[13px] font-medium text-foreground">{phaseLabel}</span>
        <Badge variant="accent" className="ml-auto">
          Agent
        </Badge>
      </div>

      {phase === "executing" && totalSteps !== undefined && stepIndex !== undefined && (
        <div className="mt-2.5 space-y-1.5">
          <div className="flex items-center justify-between text-xs text-muted">
            <span>
              Étape {stepIndex + 1}/{totalSteps}
              {currentStepTitle ? ` · ${currentStepTitle}` : ""}
            </span>
            {progress !== null && (
              <span className="tabular-nums">{progress}%</span>
            )}
          </div>
          {progress !== null && (
            <div
              className="h-1 overflow-hidden rounded-full bg-surface-active"
              role="progressbar"
              aria-valuenow={progress}
              aria-valuemin={0}
              aria-valuemax={100}
            >
              <div
                className="h-full rounded-full bg-accent transition-[width] duration-[var(--duration-slow)] ease-[var(--ease-out)]"
                style={{ width: `${progress}%` }}
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
});
