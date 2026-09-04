"use client";

import { AlertCircle, CheckCircle2 } from "lucide-react";
import type { AgentRunOutcome, AgentRunStats } from "@/lib/agent/types";
import { cn } from "@/lib/utils/cn";

interface AgentSummaryProps {
  stats: AgentRunStats;
  stopReason?: string;
  runOutcome?: AgentRunOutcome;
  className?: string;
}

export function AgentSummary({
  stats,
  stopReason,
  runOutcome,
  className,
}: AgentSummaryProps) {
  const seconds = Math.round(stats.durationMs / 1000);
  const steps = stats.planStepsExecuted ?? stats.steps;
  const total = stats.planStepsTotal;
  const isWebFailure = runOutcome === "web_unavailable";

  const stepsLabel = isWebFailure
    ? total > 0
      ? `${steps}/${total} étape${total > 1 ? "s" : ""}`
      : `${steps} étape${steps > 1 ? "s" : ""}`
    : total > 0
      ? `${total} étape${total > 1 ? "s" : ""}`
      : "Terminé";

  return (
    <div className={cn("space-y-2", className)}>
      <div
        className={cn(
          "flex items-start gap-2.5 rounded-[var(--radius-lg)] border px-3.5 py-2.5 text-sm",
          isWebFailure
            ? "border-warning/30 bg-warning-muted text-warning"
            : "border-success/30 bg-success-muted text-success"
        )}
        role="status"
      >
        {isWebFailure ? (
          <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
        ) : (
          <CheckCircle2 className="mt-0.5 h-4 w-4 shrink-0" />
        )}
        <div className="min-w-0 flex-1">
          <p className="font-medium text-foreground">
            Agent terminé · {stepsLabel}
          </p>
          <p className="mt-0.5 text-xs text-muted">
            {stats.webSearchCount} recherche{stats.webSearchCount > 1 ? "s" : ""} Web ·{" "}
            {stats.llmCalls} appel{stats.llmCalls > 1 ? "s" : ""} IA · {seconds} s
          </p>
        </div>
      </div>
      {isWebFailure && stopReason && (
        <p className="px-1 text-sm text-muted">
          Les données n&apos;ont pas pu être vérifiées sur le Web.
          {stopReason !== "Agent arrêté : aucune source Web exploitable" && (
            <> {stopReason}</>
          )}
        </p>
      )}
    </div>
  );
}
