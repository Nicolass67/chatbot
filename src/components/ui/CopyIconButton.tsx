"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Check, Copy } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface CopyIconButtonProps {
  value: string;
  className?: string;
}

async function copyToClipboard(value: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(value);
    return true;
  } catch {
    try {
      const textarea = document.createElement("textarea");
      textarea.value = value;
      textarea.style.position = "fixed";
      textarea.style.opacity = "0";
      document.body.appendChild(textarea);
      textarea.select();
      const ok = document.execCommand("copy");
      document.body.removeChild(textarea);
      return ok;
    } catch {
      return false;
    }
  }
}

export function CopyIconButton({ value, className }: CopyIconButtonProps) {
  const [copied, setCopied] = useState(false);
  const resetTimerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (resetTimerRef.current !== null) {
        window.clearTimeout(resetTimerRef.current);
      }
    };
  }, []);

  const handleCopy = useCallback(async () => {
    if (!value) return;
    const ok = await copyToClipboard(value);
    if (!ok) return;

    setCopied(true);
    if (resetTimerRef.current !== null) {
      window.clearTimeout(resetTimerRef.current);
    }
    resetTimerRef.current = window.setTimeout(() => {
      setCopied(false);
      resetTimerRef.current = null;
    }, 2000);
  }, [value]);

  return (
    <button
      type="button"
      onClick={() => void handleCopy()}
      aria-label={copied ? "Copié" : "Copier"}
      title={copied ? "Copié" : "Copier"}
      className={cn(
        "inline-flex h-7 w-7 shrink-0 items-center justify-center rounded-[var(--radius-md)] transition-[background-color,color,box-shadow] duration-[var(--duration-normal)] ease-[var(--ease-out)] active:scale-[0.96]",
        copied
          ? "bg-success-muted text-success shadow-[0_0_0_1px_color-mix(in_srgb,var(--success)_25%,transparent)]"
          : "text-muted hover:bg-surface-hover hover:text-foreground",
        className
      )}
    >
      <span className="relative flex h-3.5 w-3.5 items-center justify-center">
        <Copy
          className={cn(
            "absolute h-3.5 w-3.5 transition-all duration-[var(--duration-normal)] ease-[var(--ease-out)] motion-reduce:transition-none",
            copied ? "scale-75 opacity-0 rotate-12" : "scale-100 opacity-100 rotate-0"
          )}
          aria-hidden
        />
        <Check
          className={cn(
            "absolute h-3.5 w-3.5 motion-reduce:transition-none",
            copied ? "copy-check-pop" : "scale-75 opacity-0 -rotate-12"
          )}
          aria-hidden
        />
      </span>
    </button>
  );
}
