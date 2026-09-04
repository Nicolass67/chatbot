"use client";

import { useEffect, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { ArrowLeft, X } from "lucide-react";
import Link from "next/link";
import { IconButton } from "@/components/ui/IconButton";
import { cn } from "@/lib/utils/cn";

interface MailMobileListHeaderProps {
  className?: string;
  /** null = une catégorie Gmail est active (ni Boîte ni Non lus). */
  scope?: "inbox" | "unread" | null;
  onScopeChange?: (scope: "inbox" | "unread") => void;
  disabled?: boolean;
}

export function MailMobileListHeader({
  className,
  scope = "inbox",
  onScopeChange,
  disabled,
}: MailMobileListHeaderProps) {
  return (
    <header
      className={cn(
        "glass sticky top-0 z-[var(--z-chrome)] flex mobile-chrome-header items-center gap-1 px-2 safe-top safe-x lg:hidden",
        className
      )}
    >
      <Link
        href="/chat/new"
        className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-[var(--radius-md)] text-muted transition-colors hover:bg-surface-hover hover:text-foreground"
        aria-label="Retour au chat"
      >
        <ArrowLeft className="h-5 w-5" strokeWidth={1.75} />
      </Link>
      <p className="min-w-0 flex-1 truncate text-[15px] font-semibold tracking-[-0.02em] text-foreground">
        Mail
      </p>
      {onScopeChange && (
        <div
          role="group"
          aria-label="Portée de la boîte"
          className="flex shrink-0 rounded-[var(--radius-md)] bg-surface-hover/80 p-0.5"
        >
          <button
            type="button"
            disabled={disabled}
            onClick={() => onScopeChange("inbox")}
            className={cn(
              "rounded-[var(--radius-sm)] px-2.5 py-1.5 text-[12px] transition-colors",
              scope === "inbox"
                ? "bg-surface font-semibold text-foreground shadow-sm"
                : "text-muted hover:text-foreground"
            )}
          >
            Boîte
          </button>
          <button
            type="button"
            disabled={disabled}
            onClick={() => onScopeChange("unread")}
            className={cn(
              "rounded-[var(--radius-sm)] px-2.5 py-1.5 text-[12px] transition-colors",
              scope === "unread"
                ? "bg-surface font-semibold text-foreground shadow-sm"
                : "text-muted hover:text-foreground"
            )}
          >
            Non lus
          </button>
        </div>
      )}
    </header>
  );
}

/** Remet le zoom navigateur à 1 (iOS/Android élargissent souvent le layout). */
function resetVisualViewportZoom() {
  const meta = document.querySelector('meta[name="viewport"]');
  if (!(meta instanceof HTMLMetaElement)) return () => undefined;

  const previous = meta.getAttribute("content") ?? "";
  meta.setAttribute(
    "content",
    "width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover"
  );

  return () => {
    meta.setAttribute(
      "content",
      previous || "width=device-width, initial-scale=1, viewport-fit=cover"
    );
  };
}

interface MailReadingModalProps {
  open: boolean;
  title?: string;
  loading?: boolean;
  onClose: () => void;
  children: ReactNode;
}

/** Lecture mail plein écran mobile — chrome glass, contenu lisible. */
export function MailReadingModal({
  open,
  title,
  loading,
  onClose,
  children,
}: MailReadingModalProps) {
  const [visible, setVisible] = useState(false);
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    if (!open) {
      setVisible(false);
      return;
    }
    const id = requestAnimationFrame(() => {
      requestAnimationFrame(() => setVisible(true));
    });
    return () => cancelAnimationFrame(id);
  }, [open]);

  useEffect(() => {
    if (!open) return;
    const prevBodyOverflow = document.body.style.overflow;
    const prevHtmlOverflowX = document.documentElement.style.overflowX;
    document.body.style.overflow = "hidden";
    document.documentElement.style.overflowX = "hidden";
    const restoreViewport = resetVisualViewportZoom();

    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prevBodyOverflow;
      document.documentElement.style.overflowX = prevHtmlOverflowX;
      restoreViewport();
      window.removeEventListener("keydown", onKey);
    };
  }, [open, onClose]);

  if (!open || !mounted || typeof document === "undefined") return null;

  return createPortal(
    <div
      className={cn(
        "fixed inset-0 z-[var(--z-modal)] flex w-full max-w-[100vw] flex-col overflow-x-hidden overscroll-none transition-opacity duration-[var(--duration-normal)] ease-[var(--ease-out)] lg:hidden motion-reduce:transition-none",
        visible ? "opacity-100" : "opacity-0"
      )}
      role="dialog"
      aria-modal="true"
      aria-label={loading ? "Chargement du message" : title ?? "Message"}
    >
      <div
        className="absolute inset-0 bg-[color-mix(in_srgb,var(--background)_82%,transparent)] backdrop-blur-[6px]"
        aria-hidden
      />
      <header className="glass relative z-10 flex w-full mobile-chrome-header shrink-0 items-center gap-1 px-2 safe-top safe-x">
        <IconButton variant="ghost" size="md" label="Fermer" onClick={onClose}>
          <X className="h-5 w-5" strokeWidth={1.75} />
        </IconButton>
        <p className="min-w-0 flex-1 truncate text-[15px] font-semibold tracking-[-0.02em] text-foreground">
          {loading ? "Chargement…" : title ?? "Message"}
        </p>
      </header>
      <div className="relative z-10 min-h-0 w-full min-w-0 flex-1 overflow-x-hidden overflow-y-hidden">
        {children}
      </div>
    </div>,
    document.body
  );
}
