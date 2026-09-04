"use client";

import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { MessageSquare, X } from "lucide-react";
import { IconButton } from "@/components/ui/IconButton";
import { cn } from "@/lib/utils/cn";

const CLOSE_MS = 260;

type Phase = "closed" | "opening" | "open" | "closing";

export interface AssistantFabShellProps {
  open: boolean;
  onOpen: () => void;
  onClose: () => void;
  children: ReactNode;
  title: string;
  openLabel: string;
  /** Conserver les children montés même fermé (historique Files). */
  keepMounted?: boolean;
}

/** Relance les keyframes sans flash (pas de retrait de classe). */
function restartCssAnimation(el: HTMLElement | null) {
  if (!el) return;
  el.style.animation = "none";
  void el.offsetWidth;
  el.style.removeProperty("animation");
}

/**
 * Pastille → panneau assistant.
 * Ouverture : keyframes CSS.
 * Fermeture : transition CSS.
 */
export function AssistantFabShell({
  open,
  onOpen,
  onClose,
  children,
  title,
  openLabel,
  keepMounted = false,
}: AssistantFabShellProps) {
  const [phase, setPhase] = useState<Phase>(open ? "open" : "closed");
  const closeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const backdropRef = useRef<HTMLButtonElement>(null);
  const contentRef = useRef<HTMLDivElement>(null);

  useLayoutEffect(() => {
    if (closeTimer.current) {
      clearTimeout(closeTimer.current);
      closeTimer.current = null;
    }

    if (open) {
      setPhase("opening");
      return;
    }

    setPhase((prev) => (prev === "closed" ? "closed" : "closing"));
    closeTimer.current = setTimeout(() => {
      setPhase("closed");
      closeTimer.current = null;
    }, CLOSE_MS);

    return () => {
      if (closeTimer.current) clearTimeout(closeTimer.current);
    };
  }, [open]);

  // Après commit en phase opening : garantir que les keyframes partent bien
  useLayoutEffect(() => {
    if (phase !== "opening") return;
    restartCssAnimation(panelRef.current);
    restartCssAnimation(backdropRef.current);
    restartCssAnimation(contentRef.current);
  }, [phase]);

  const present = phase !== "closed";
  const fabVisible = phase === "closed";
  const mountOverlay = keepMounted || present;

  useEffect(() => {
    if (!present) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [present, onClose]);

  return (
    <>
      <button
        type="button"
        onClick={onOpen}
        tabIndex={fabVisible ? 0 : -1}
        aria-hidden={!fabVisible}
        className={cn(
          "glass-thick fixed bottom-[max(1.25rem,env(safe-area-inset-bottom))] right-4 z-[var(--z-fab)] flex h-11 w-11 items-center justify-center rounded-full text-foreground",
          "transition-[opacity,transform] duration-200 ease-[var(--ease-out)]",
          "hover:scale-[1.04] active:scale-95",
          "motion-reduce:transition-none motion-reduce:hover:scale-100",
          fabVisible
            ? "pointer-events-auto scale-100 opacity-100"
            : "pointer-events-none scale-90 opacity-0"
        )}
        aria-label={openLabel}
      >
        <MessageSquare className="h-4 w-4" strokeWidth={1.75} />
      </button>

      {mountOverlay && (
        <div
          className={cn(
            "fixed inset-0",
            present ? "z-[var(--z-fab)]" : "pointer-events-none z-[-1]"
          )}
          role="dialog"
          aria-modal={present}
          aria-label={title}
          aria-hidden={!present}
        >
          <button
            ref={backdropRef}
            type="button"
            tabIndex={present ? 0 : -1}
            className={cn(
              "absolute inset-0 bg-black/50 backdrop-blur-[2px]",
              phase === "opening" && "assistant-fab-backdrop-in",
              phase === "open" && "opacity-100",
              phase === "closing" && "assistant-fab-backdrop-out",
              phase === "closed" && "opacity-0"
            )}
            aria-label="Fermer l'assistant"
            onClick={onClose}
          />

          <div
            ref={panelRef}
            className={cn(
              "absolute bottom-[max(1rem,env(safe-area-inset-bottom))] right-4",
              "flex h-[min(92dvh,760px)] w-[calc(100%-2rem)] max-w-[420px] flex-col overflow-hidden",
              "glass-thick rounded-[var(--radius-2xl)]",
              "origin-bottom-right will-change-transform",
              "sm:bottom-4 sm:right-4 sm:h-[min(85dvh,680px)]",
              "max-sm:bottom-0 max-sm:right-0 max-sm:w-full max-sm:max-w-none",
              "max-sm:rounded-b-none max-sm:rounded-t-[var(--radius-2xl)]",
              phase === "opening" && "assistant-fab-panel-in",
              phase === "open" && "opacity-100",
              phase === "closing" && "assistant-fab-panel-out",
              phase === "closed" && "opacity-0"
            )}
            style={
              phase === "open"
                ? { transform: "scale(1) translateZ(0)", opacity: 1 }
                : undefined
            }
            onAnimationEnd={(e) => {
              if (e.target !== e.currentTarget) return;
              if (phase === "opening") setPhase("open");
            }}
          >
            <div
              ref={contentRef}
              className={cn(
                "flex h-full min-h-0 flex-col",
                phase === "opening" && "assistant-fab-content-in",
                phase === "open" && "opacity-100",
                (phase === "closing" || phase === "closed") &&
                  "pointer-events-none opacity-0"
              )}
            >
              <header className="flex mobile-chrome-header shrink-0 items-center justify-between gap-2 px-2">
                <div className="px-2 text-[13px] font-medium text-foreground">
                  {title}
                </div>
                <IconButton
                  variant="ghost"
                  size="md"
                  label="Fermer"
                  onClick={onClose}
                >
                  <X className="h-4 w-4" />
                </IconButton>
              </header>
              <div className="min-h-0 flex-1 overflow-hidden">{children}</div>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
