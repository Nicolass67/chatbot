"use client";

import { useEffect, useId, useRef, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { X } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { IconButton } from "@/components/ui/IconButton";

interface MobileBottomSheetProps {
  open: boolean;
  onClose: () => void;
  title: string;
  description?: string;
  children: ReactNode;
  className?: string;
  /** Contenu sous le titre (ex. pastilles) — avant le scroll. */
  headerExtra?: ReactNode;
}

/** Bottom sheet mobile partagé (chat / files / mail). */
export function MobileBottomSheet({
  open,
  onClose,
  title,
  description,
  children,
  className,
  headerExtra,
}: MobileBottomSheetProps) {
  const titleId = useId();
  const panelRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    const t = window.setTimeout(() => {
      const focusable = panelRef.current?.querySelector<HTMLElement>(
        "button,input,textarea,select,[tabindex]:not([tabindex='-1'])"
      );
      focusable?.focus();
    }, 0);
    return () => {
      document.body.style.overflow = prev;
      window.removeEventListener("keydown", onKey);
      window.clearTimeout(t);
    };
  }, [open, onClose]);

  if (!open || typeof document === "undefined") return null;

  return createPortal(
    <div className="fixed inset-0 z-[var(--z-modal)] flex items-end justify-center sm:items-center sm:p-4">
      <button
        type="button"
        className="absolute inset-0 bg-black/50 backdrop-blur-[2px]"
        aria-label="Fermer"
        onClick={onClose}
      />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        className={cn(
          "glass-thick relative z-10 flex max-h-[min(85dvh,640px)] w-full max-w-md flex-col",
          "rounded-t-[var(--radius-2xl)] sm:rounded-[var(--radius-2xl)]",
          "animate-[sheet-up_var(--duration-normal)_var(--ease-out)]",
          "pb-[max(0.5rem,env(safe-area-inset-bottom))]",
          className
        )}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mx-auto mt-2 h-1 w-10 shrink-0 rounded-full bg-border-strong/70 sm:hidden" aria-hidden />
        <div className="flex shrink-0 items-start justify-between gap-3 px-4 pb-2 pt-3">
          <div className="min-w-0 flex-1">
            <h2 id={titleId} className="truncate text-sm font-semibold text-foreground">
              {title}
            </h2>
            {description ? (
              <p className="mt-0.5 text-xs text-muted">{description}</p>
            ) : null}
            {headerExtra}
          </div>
          <IconButton
            label="Fermer"
            size="sm"
            onClick={onClose}
            className="!h-9 !w-9 max-md:!h-9 max-md:!w-9"
          >
            <X className="h-4 w-4" />
          </IconButton>
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain px-2 pb-2">
          {children}
        </div>
      </div>
    </div>,
    document.body
  );
}

interface MobileSheetActionProps {
  label: string;
  icon?: ReactNode;
  onClick: () => void;
  destructive?: boolean;
  disabled?: boolean;
}

export function MobileSheetAction({
  label,
  icon,
  onClick,
  destructive,
  disabled,
}: MobileSheetActionProps) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className={cn(
        "flex min-h-11 w-full items-center gap-3 rounded-[var(--radius-md)] px-3 py-2.5 text-left text-sm transition-colors",
        "hover:bg-surface-hover disabled:cursor-not-allowed disabled:opacity-50",
        destructive ? "text-error" : "text-foreground"
      )}
    >
      {icon ? (
        <span className={cn("shrink-0", destructive ? "text-error" : "text-muted")}>
          {icon}
        </span>
      ) : null}
      {label}
    </button>
  );
}
