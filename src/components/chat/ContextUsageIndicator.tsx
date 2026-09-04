"use client";

import { useEffect, useRef, useState } from "react";
import type { ContextSnapshot } from "@/lib/context/builder";
import type { RuntimeUsage } from "@/lib/runtime/types";
import { cn } from "@/lib/utils/cn";

function formatTokens(n: number): string {
  if (n >= 1000) return `${(n / 1000).toFixed(1)}k`;
  return String(n);
}

function usageLevel(percent: number): "normal" | "warning" | "danger" {
  if (percent >= 85) return "danger";
  if (percent >= 70) return "warning";
  return "normal";
}

const levelVariant = {
  normal: "text-muted",
  warning: "text-warning",
  danger: "text-error",
} as const;

interface ContextUsageIndicatorProps {
  snapshot: ContextSnapshot | null;
  lastGeneration?: RuntimeUsage | null;
  loading?: boolean;
  className?: string;
}

export function ContextUsageIndicator({
  snapshot,
  lastGeneration,
  loading,
  className,
}: ContextUsageIndicatorProps) {
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onDocClick = (e: MouseEvent) => {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onDocClick);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onDocClick);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, []);

  if (loading || !snapshot) {
    return (
      <span className={cn("text-[10px] text-muted-foreground", className)}>
        Contexte…
      </span>
    );
  }

  const level = usageLevel(snapshot.usedPercent);
  const compact = `${formatTokens(snapshot.conversationTokens)}/${formatTokens(snapshot.contextLengthMax)}`;

  return (
    <div ref={rootRef} className={cn("relative shrink-0", className)}>
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className={cn(
          "min-h-[32px] rounded-[var(--radius-md)] px-2 py-1 text-[10px] tabular-nums transition-colors hover:bg-surface-hover md:min-h-0",
          levelVariant[level]
        )}
        aria-expanded={open}
        title="Utilisation du contexte"
      >
        {compact}
      </button>

      {open && (
        <div
          className="absolute bottom-full right-0 z-50 mb-2 w-[min(280px,calc(100vw-2rem))] rounded-[var(--radius-xl)] border border-border bg-surface-elevated p-3 text-xs shadow-[var(--shadow-popover)] animate-[toast-in_var(--duration-normal)_var(--ease-out)_forwards]"
          role="dialog"
          aria-label="Détails du contexte"
        >
          <p className="mb-2 font-semibold text-foreground">Contexte</p>
          <dl className="space-y-1 text-muted">
            <div className="flex justify-between gap-4">
              <dt>Conversation</dt>
              <dd className="tabular-nums text-foreground">
                {snapshot.conversationTokens.toLocaleString("fr-FR")} tokens
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt>Maximum</dt>
              <dd className="tabular-nums text-foreground">
                {snapshot.contextLengthMax.toLocaleString("fr-FR")}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt>Utilisé</dt>
              <dd className={cn("tabular-nums", levelVariant[level])}>
                {snapshot.usedPercent.toFixed(1)} %
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt>Restant</dt>
              <dd className="tabular-nums text-foreground">
                {snapshot.remainingPercent.toFixed(1)} %
              </dd>
            </div>
          </dl>

          <div className="mt-2 border-t border-border-subtle pt-2">
            <p className="mb-1 text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
              Détail (estimation)
            </p>
            <dl className="grid grid-cols-2 gap-x-2 gap-y-0.5 text-[10px] text-muted">
              <dt>Système</dt>
              <dd className="text-right tabular-nums">{snapshot.breakdown.system}</dd>
              <dt>Mémoires</dt>
              <dd className="text-right tabular-nums">{snapshot.breakdown.memories}</dd>
              <dt>Résumé</dt>
              <dd className="text-right tabular-nums">{snapshot.breakdown.summary}</dd>
              <dt>Documents</dt>
              <dd className="text-right tabular-nums">{snapshot.breakdown.documents}</dd>
              <dt>Outils / Web</dt>
              <dd className="text-right tabular-nums">{snapshot.breakdown.tools}</dd>
              <dt>Messages</dt>
              <dd className="text-right tabular-nums">{snapshot.breakdown.messages}</dd>
              <dt>Images</dt>
              <dd className="text-right tabular-nums">{snapshot.breakdown.images}</dd>
            </dl>
            <p className="mt-1 text-[9px] text-muted-foreground">
              {snapshot.includedMessageCount}/{snapshot.totalMessageCount} messages inclus
              {snapshot.hasSummary ? " · résumé actif" : ""}
            </p>
          </div>

          {lastGeneration && lastGeneration.source === "lm_studio" && (
            <div className="mt-2 border-t border-border-subtle pt-2">
              <p className="mb-1 font-semibold text-foreground">Dernière génération</p>
              <dl className="space-y-0.5 text-muted">
                {lastGeneration.promptTokens !== undefined && (
                  <div className="flex justify-between gap-4">
                    <dt>Prompt</dt>
                    <dd className="tabular-nums text-foreground">
                      {lastGeneration.promptTokens.toLocaleString("fr-FR")}
                    </dd>
                  </div>
                )}
                {lastGeneration.completionTokens !== undefined && (
                  <div className="flex justify-between gap-4">
                    <dt>Générés</dt>
                    <dd className="tabular-nums text-foreground">
                      {lastGeneration.completionTokens.toLocaleString("fr-FR")}
                    </dd>
                  </div>
                )}
                {lastGeneration.reasoningTokens !== undefined &&
                  lastGeneration.reasoningTokens > 0 && (
                    <div className="flex justify-between gap-4">
                      <dt>Raisonnement</dt>
                      <dd className="tabular-nums text-foreground">
                        {lastGeneration.reasoningTokens.toLocaleString("fr-FR")}
                      </dd>
                    </div>
                  )}
                {lastGeneration.tokensPerSecond !== undefined && (
                  <div className="flex justify-between gap-4">
                    <dt>Vitesse</dt>
                    <dd className="tabular-nums text-foreground">
                      {lastGeneration.tokensPerSecond.toFixed(1)} tok/s
                    </dd>
                  </div>
                )}
                {lastGeneration.timeToFirstTokenMs !== undefined && (
                  <div className="flex justify-between gap-4">
                    <dt>1er token</dt>
                    <dd className="tabular-nums text-foreground">
                      {(lastGeneration.timeToFirstTokenMs / 1000).toFixed(2)} s
                    </dd>
                  </div>
                )}
                {lastGeneration.totalGenerationMs !== undefined && (
                  <div className="flex justify-between gap-4">
                    <dt>Durée</dt>
                    <dd className="tabular-nums text-foreground">
                      {(lastGeneration.totalGenerationMs / 1000).toFixed(1)} s
                    </dd>
                  </div>
                )}
              </dl>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
