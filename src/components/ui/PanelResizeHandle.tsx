"use client";

import {
  useCallback,
  useEffect,
  useRef,
  type PointerEvent as ReactPointerEvent,
} from "react";
import { cn } from "@/lib/utils/cn";

interface PanelResizeHandleProps {
  width: number;
  onWidthChange: (width: number) => void;
  min?: number;
  max?: number;
  /**
   * `after` : poignée à droite d’un panneau gauche (tirer à droite = élargir).
   * `before` : poignée à gauche d’un panneau droit (tirer à gauche = élargir).
   */
  placement?: "after" | "before";
  label?: string;
  className?: string;
  /** Afficher dès ce breakpoint (défaut: toujours visible). */
  showFrom?: "always" | "md" | "lg";
}

/**
 * Poignée de redimensionnement entre deux panneaux.
 */
export function PanelResizeHandle({
  width,
  onWidthChange,
  min = 240,
  max = 560,
  placement = "after",
  label = "Redimensionner le panneau",
  className,
  showFrom = "always",
}: PanelResizeHandleProps) {
  const dragging = useRef(false);
  const startX = useRef(0);
  const startW = useRef(width);

  const onPointerMove = useCallback(
    (ev: PointerEvent) => {
      if (!dragging.current) return;
      const rawDelta = ev.clientX - startX.current;
      const delta = placement === "after" ? rawDelta : -rawDelta;
      const next = Math.min(max, Math.max(min, startW.current + delta));
      onWidthChange(next);
    },
    [max, min, onWidthChange, placement]
  );

  const stopDrag = useCallback(() => {
    if (!dragging.current) return;
    dragging.current = false;
    document.body.style.removeProperty("cursor");
    document.body.style.removeProperty("user-select");
    window.removeEventListener("pointermove", onPointerMove);
    window.removeEventListener("pointerup", stopDrag);
    window.removeEventListener("pointercancel", stopDrag);
  }, [onPointerMove]);

  useEffect(() => () => stopDrag(), [stopDrag]);

  const onPointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (e.button !== 0) return;
    e.preventDefault();
    e.stopPropagation();
    dragging.current = true;
    startX.current = e.clientX;
    startW.current = width;
    document.body.style.cursor = "col-resize";
    document.body.style.userSelect = "none";
    window.addEventListener("pointermove", onPointerMove);
    window.addEventListener("pointerup", stopDrag);
    window.addEventListener("pointercancel", stopDrag);
  };

  return (
    <div
      role="separator"
      aria-orientation="vertical"
      aria-label={label}
      aria-valuenow={Math.round(width)}
      aria-valuemin={min}
      aria-valuemax={max}
      tabIndex={0}
      onPointerDown={onPointerDown}
      onKeyDown={(e) => {
        const step = e.shiftKey ? 24 : 12;
        if (e.key === "ArrowLeft") {
          e.preventDefault();
          onWidthChange(
            Math.min(
              max,
              Math.max(min, width + (placement === "after" ? -step : step))
            )
          );
        } else if (e.key === "ArrowRight") {
          e.preventDefault();
          onWidthChange(
            Math.min(
              max,
              Math.max(min, width + (placement === "after" ? step : -step))
            )
          );
        }
      }}
      className={cn(
        "group relative z-20 w-1 shrink-0 cursor-col-resize touch-none",
        "bg-transparent hover:bg-accent/60 active:bg-accent",
        "focus-visible:outline-none focus-visible:bg-accent/60",
        /* Zone cliquable élargie sans prendre plus de place */
        "before:absolute before:inset-y-0 before:-left-1.5 before:-right-1.5 before:content-['']",
        showFrom === "md" && "hidden md:block",
        showFrom === "lg" && "hidden lg:block",
        className
      )}
    />
  );
}
