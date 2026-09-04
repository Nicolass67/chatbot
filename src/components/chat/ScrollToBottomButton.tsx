"use client";

import { ArrowDown } from "lucide-react";
import { cn } from "@/lib/utils/cn";

interface ScrollToBottomButtonProps {
  visible: boolean;
  onClick: () => void;
}

export function ScrollToBottomButton({
  visible,
  onClick,
}: ScrollToBottomButtonProps) {
  return (
    <button
      type="button"
      aria-label="Revenir en bas du chat"
      title="Revenir en bas"
      onClick={onClick}
      className={cn(
        "absolute bottom-5 right-4 z-[var(--z-drawer-scrim)] flex h-11 w-11 items-center justify-center rounded-full glass-thick text-muted transition-[opacity,transform,color] duration-200 ease-[var(--ease-out)] hover:text-foreground active:scale-95 motion-reduce:transition-none",
        visible
          ? "pointer-events-auto translate-y-0 opacity-100"
          : "pointer-events-none translate-y-2 opacity-0"
      )}
    >
      <ArrowDown className="h-4 w-4" aria-hidden />
    </button>
  );
}
