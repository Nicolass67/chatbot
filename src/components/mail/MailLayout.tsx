"use client";

import Link from "next/link";
import { cn } from "@/lib/utils/cn";
import { PanelResizeHandle } from "@/components/ui/PanelResizeHandle";
import { useMediaQuery } from "@/hooks/useMediaQuery";
import { useResizableWidth } from "@/hooks/useResizableWidth";

interface MailLayoutProps {
  children: React.ReactNode;
  sidebar?: React.ReactNode;
  banner?: React.ReactNode;
  mobileHeader?: React.ReactNode;
  overlay?: React.ReactNode;
  mobileHideList?: boolean;
  mobileHideDetail?: boolean;
}

export function MailLayout({
  children,
  sidebar,
  banner,
  mobileHeader,
  overlay,
  mobileHideList = false,
  mobileHideDetail = false,
}: MailLayoutProps) {
  const isDesktop = useMediaQuery("(min-width: 1024px)");
  const { width, setWidth, min, max } = useResizableWidth({
    // v2 : largeur par défaut calée pour une seule ligne de catégories
    storageKey: "ui.mailListWidth.v2",
    defaultWidth: 540,
    min: 320,
    max: 720,
  });

  return (
    <div className="ambient-canvas flex h-[100dvh] flex-col">
      {mobileHeader}

      <header className="glass mx-3 mt-2 hidden items-center gap-4 rounded-[var(--radius-2xl)] px-5 py-2.5 lg:flex">
        <Link
          href="/chat/new"
          className="text-[13px] text-muted hover:text-foreground"
        >
          Chat
        </Link>
        <span className="text-muted-foreground" aria-hidden>
          /
        </span>
        <div className="text-[13px] font-semibold tracking-[-0.01em] text-foreground">
          Mail
        </div>
      </header>

      {banner}

      <div className="flex min-h-0 flex-1 overflow-hidden">
        {sidebar && (
          <>
            <div
              className={cn(
                "flex h-full shrink-0 flex-col",
                isDesktop && "py-2 pl-2",
                mobileHideList && "hidden lg:flex",
                !isDesktop && "w-full"
              )}
            >
              <div
                className={cn(
                  "flex min-h-0 flex-1 flex-col overflow-hidden",
                  isDesktop && "glass-sidebar"
                )}
                style={isDesktop ? { width } : undefined}
              >
                {sidebar}
              </div>
            </div>
            {isDesktop && (
              <PanelResizeHandle
                width={width}
                onWidthChange={setWidth}
                min={min}
                max={max}
                placement="after"
                label="Redimensionner la liste mail"
                showFrom="always"
              />
            )}
          </>
        )}

        <main
          className={cn(
            "flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden",
            mobileHideDetail && "hidden lg:flex"
          )}
        >
          {children}
        </main>
      </div>

      {overlay}
    </div>
  );
}
