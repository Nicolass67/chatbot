"use client";

import { cn } from "@/lib/utils/cn";

interface SwitchProps {
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
  label: string;
  description?: string;
  id?: string;
  className?: string;
}

export function Switch({
  checked,
  onChange,
  disabled,
  label,
  description,
  id,
  className,
}: SwitchProps) {
  const switchId = id ?? label.replace(/\s+/g, "-").toLowerCase();

  return (
    <div
      className={cn(
        "flex items-start gap-3",
        disabled && "pointer-events-none opacity-50",
        className
      )}
    >
      <button
        id={switchId}
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={cn(
          "relative mt-0.5 h-5 w-9 shrink-0 rounded-full transition-colors duration-[var(--duration-fast)] focus-visible:outline-none",
          checked ? "bg-accent" : "bg-surface-active"
        )}
      >
        <span
          className={cn(
            "absolute top-0.5 left-0.5 h-4 w-4 rounded-full bg-white shadow-sm transition-transform duration-[var(--duration-fast)]",
            checked && "translate-x-4"
          )}
        />
      </button>
      <div className="min-w-0 flex-1">
        <label htmlFor={switchId} className="block cursor-pointer text-sm text-foreground">
          {label}
        </label>
        {description && (
          <p className="mt-0.5 text-xs text-muted">{description}</p>
        )}
      </div>
    </div>
  );
}
