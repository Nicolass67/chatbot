"use client";

import { Sidebar, type ConversationItem } from "./Sidebar";
import { cn } from "@/lib/utils/cn";

interface MobileDrawerProps {
  open: boolean;
  onClose: () => void;
  conversations: ConversationItem[];
  conversationsLoaded?: boolean;
  onNewChat: () => void;
  onDelete: (id: string) => void;
  onRename: (id: string, title: string) => void;
}

/** Panneau latéral mobile uniquement — le bouton menu vit dans ChatHeader. */
export function MobileDrawer({
  open,
  onClose,
  ...sidebarProps
}: MobileDrawerProps) {
  return (
    <>
      {open && (
        <div
          className="fixed inset-0 z-[var(--z-drawer-scrim)] bg-black/50 backdrop-blur-[2px] md:hidden"
          onClick={onClose}
          aria-hidden
        />
      )}

      <div
        className={cn(
          "fixed z-[var(--z-drawer)] w-[min(20rem,86vw)] transition-transform duration-[var(--duration-normal)] ease-[var(--ease-out)] md:hidden",
          "top-[max(0.5rem,env(safe-area-inset-top))] bottom-[max(0.5rem,env(safe-area-inset-bottom))] left-[max(0.5rem,env(safe-area-inset-left))]",
          open ? "translate-x-0" : "-translate-x-full"
        )}
        role="dialog"
        aria-modal={open}
        aria-hidden={!open}
        aria-label="Navigation"
      >
        <Sidebar {...sidebarProps} onClose={onClose} resizable={false} />
      </div>
    </>
  );
}
