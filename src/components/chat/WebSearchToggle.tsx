"use client";

import { Globe } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface WebSearchToggleProps {
  enabled: boolean;
  disabled?: boolean;
  onChange: (enabled: boolean) => void;
  className?: string;
}

export function WebSearchToggle({
  enabled,
  disabled,
  onChange,
  className,
}: WebSearchToggleProps) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={() => !disabled && onChange(!enabled)}
      className={cn(
        "inline-flex min-h-[32px] items-center gap-1.5 rounded-[var(--radius-md)] px-2 py-1 text-[11px] transition-colors md:min-h-0 md:text-xs",
        enabled
          ? "bg-accent-subtle font-medium text-accent"
          : "text-muted hover:bg-surface-hover hover:text-foreground",
        disabled && "cursor-not-allowed opacity-50",
        className
      )}
      aria-pressed={enabled}
      title={enabled ? "Recherche Web activée" : "Recherche Web désactivée"}
    >
      <Globe className="h-3.5 w-3.5 shrink-0" strokeWidth={1.75} />
      <span className="hidden sm:inline">{enabled ? "Web" : "Web off"}</span>
    </button>
  );
}
