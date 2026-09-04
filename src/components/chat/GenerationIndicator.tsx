"use client";

import { cn } from "@/lib/utils/cn";

interface GenerationIndicatorProps {
  label?: string;
  className?: string;
}

export function GenerationIndicator({
  label = "Génération…",
  className,
}: GenerationIndicatorProps) {
  return (
    <div
      className={cn("flex items-center gap-2 text-xs text-muted", className)}
      role="status"
      aria-live="polite"
    >
      <span className="pulse-dot" aria-hidden />
      <span>{label}</span>
    </div>
  );
}
