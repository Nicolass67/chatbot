"use client";

import { useState } from "react";
import { Menu, X } from "lucide-react";
import { HeaderStatusCluster } from "@/components/layout/HeaderStatusCluster";
import { useChatMobileNav } from "@/components/chat/ChatMobileNavContext";
import { IconButton } from "@/components/ui/IconButton";
import { MobileBottomSheet } from "@/components/ui/MobileBottomSheet";
import type { WebRuntimeStatus } from "@/components/layout/WebStatusBadge";
import type { ModelRuntimeSnapshot, RuntimeStatus } from "@/lib/runtime/types";
import { cn } from "@/lib/utils/cn";

interface ChatHeaderProps {
  title: string;
  runtimeStatus: RuntimeStatus;
  modelRuntime: ModelRuntimeSnapshot | null;
  activeModelLabel?: string;
  webStatus: WebRuntimeStatus;
  webStatusMessage?: string;
}

function isRuntimeActive(status: RuntimeStatus): boolean {
  return status === "READY" || status === "BUSY";
}

function statusDotClass(
  runtimeStatus: RuntimeStatus,
  webStatus: WebRuntimeStatus
): string {
  if (runtimeStatus === "ERROR" || webStatus === "unavailable") return "bg-error";
  if (
    runtimeStatus === "STARTING" ||
    runtimeStatus === "BOOTING_SERVICES" ||
    runtimeStatus === "LOADING_MODEL" ||
    webStatus === "starting"
  ) {
    return "bg-warning";
  }
  if (isRuntimeActive(runtimeStatus)) return "bg-success";
  return "bg-muted-foreground";
}

export function ChatHeader({
  title,
  runtimeStatus,
  modelRuntime,
  activeModelLabel,
  webStatus,
  webStatusMessage,
}: ChatHeaderProps) {
  const mobileNav = useChatMobileNav();
  const [statusOpen, setStatusOpen] = useState(false);

  return (
    <>
      <header className="glass sticky top-0 z-[var(--z-chrome)] flex shrink-0 items-center justify-between gap-2 px-3 pb-2.5 pt-[max(0.5rem,env(safe-area-inset-top))] safe-x md:mx-3 md:mt-2 md:gap-3 md:rounded-[var(--radius-2xl)] md:px-5 md:pb-3 md:pt-3">
        {mobileNav && (
          <IconButton
            variant="ghost"
            size="md"
            label={mobileNav.open ? "Fermer le menu" : "Ouvrir le menu"}
            onClick={mobileNav.onToggle}
            className="md:hidden"
          >
            {mobileNav.open ? (
              <X className="h-5 w-5" strokeWidth={1.75} />
            ) : (
              <Menu className="h-5 w-5" strokeWidth={1.75} />
            )}
          </IconButton>
        )}
        <h2 className="min-w-0 flex-1 truncate text-[15px] font-semibold tracking-[-0.02em] text-foreground">
          {title}
        </h2>

        {/* Mobile: un seul indicateur → sheet */}
        <button
          type="button"
          onClick={() => setStatusOpen(true)}
          className={cn(
            "inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-[var(--radius-md)]",
            "text-muted transition-colors hover:bg-surface-hover hover:text-foreground md:hidden"
          )}
          aria-label="Statut système"
          title="Statut système"
        >
          <span
            className={cn(
              "h-2.5 w-2.5 rounded-full ring-2 ring-border-subtle",
              statusDotClass(runtimeStatus, webStatus)
            )}
            aria-hidden
          />
        </button>

        {/* Desktop: cluster complet */}
        <HeaderStatusCluster
          className="hidden md:flex"
          runtimeStatus={runtimeStatus}
          modelRuntime={modelRuntime}
          activeModelLabel={activeModelLabel}
          webStatus={webStatus}
          webStatusMessage={webStatusMessage}
        />
      </header>

      <MobileBottomSheet
        open={statusOpen}
        onClose={() => setStatusOpen(false)}
        title="Statut"
        description="Runtime, web et modèle"
      >
        <div className="px-2 py-2">
          <HeaderStatusCluster
            align="start"
            runtimeStatus={runtimeStatus}
            modelRuntime={modelRuntime}
            activeModelLabel={activeModelLabel}
            webStatus={webStatus}
            webStatusMessage={webStatusMessage}
          />
        </div>
      </MobileBottomSheet>
    </>
  );
}
