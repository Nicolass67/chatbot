"use client";

import Link from "next/link";
import { ArrowLeft, Menu, Settings } from "lucide-react";
import { cn } from "@/lib/utils/cn";
import { IconButton } from "@/components/ui/IconButton";
import { PanelResizeHandle } from "@/components/ui/PanelResizeHandle";
import { useResizableWidth } from "@/hooks/useResizableWidth";

interface FilesLayoutProps {
  children: React.ReactNode;
  rootsNav: React.ReactNode;
  toolbar: React.ReactNode;
  banner?: React.ReactNode;
  preview?: React.ReactNode;
  previewOpen?: boolean;
  previewWidth?: number;
  onPreviewWidthChange?: (width: number) => void;
  overlay?: React.ReactNode;
  rootsDrawerOpen?: boolean;
  onToggleRootsDrawer?: () => void;
  onCloseRootsDrawer?: () => void;
  mobilePreviewFullscreen?: boolean;
  onCloseMobilePreview?: () => void;
}

export function FilesLayout({
  children,
  rootsNav,
  toolbar,
  banner,
  preview,
  previewOpen = false,
  previewWidth = 360,
  onPreviewWidthChange,
  overlay,
  rootsDrawerOpen = false,
  onToggleRootsDrawer,
  onCloseRootsDrawer,
  mobilePreviewFullscreen = false,
  onCloseMobilePreview,
}: FilesLayoutProps) {
  const rootsPanel = useResizableWidth({
    storageKey: "ui.filesRootsWidth",
    defaultWidth: 208,
    min: 160,
    max: 360,
  });

  const previewPanel = useResizableWidth({
    storageKey: "ui.filesPreviewWidth",
    defaultWidth: previewWidth,
    min: 280,
    max: 640,
  });

  // Sync controlled previewWidth from parent when provided
  const effectivePreviewWidth = onPreviewWidthChange
    ? previewWidth
    : previewPanel.width;
  const setPreviewWidth = onPreviewWidthChange ?? previewPanel.setWidth;

  return (
    <div className="ambient-canvas flex h-[100dvh] flex-col">
      <header className="glass mx-2 mt-[max(0.5rem,env(safe-area-inset-top))] flex mobile-chrome-header items-center gap-1 rounded-[var(--radius-2xl)] px-2 safe-x lg:mx-3 lg:mt-2 lg:gap-4 lg:px-5 lg:py-2.5">
        <Link
          href="/chat/new"
          className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-[var(--radius-md)] text-muted transition-colors hover:bg-surface-hover/50 hover:text-foreground lg:hidden"
          aria-label="Retour au chat"
        >
          <ArrowLeft className="h-5 w-5" strokeWidth={1.75} />
        </Link>
        <IconButton
          label="Sources"
          className="lg:hidden"
          onClick={() => onToggleRootsDrawer?.()}
        >
          <Menu className="h-5 w-5" strokeWidth={1.75} />
        </IconButton>
        <Link
          href="/chat/new"
          className="hidden text-[13px] text-muted hover:text-foreground lg:inline"
        >
          Chat
        </Link>
        <span className="hidden text-muted-foreground lg:inline" aria-hidden>
          /
        </span>
        <div className="min-w-0 flex-1 text-[15px] font-semibold tracking-[-0.02em] text-foreground lg:text-[13px] lg:tracking-[-0.01em]">
          Files
        </div>
        <div className="ml-auto flex items-center gap-1">
          <Link
            href="/settings/files"
            className="inline-flex h-11 w-11 items-center justify-center rounded-[var(--radius-md)] text-muted hover:bg-surface-hover/50 hover:text-foreground lg:h-9 lg:w-9"
            aria-label="Paramètres Files"
          >
            <Settings className="h-4 w-4" strokeWidth={1.75} />
          </Link>
        </div>
      </header>

      {banner}

      <div className="relative flex min-h-0 flex-1 overflow-hidden">
        <div className="hidden py-2 pl-2 lg:block">
          <nav
            className="glass-sidebar h-full shrink-0 overflow-hidden p-3"
            style={{ width: rootsPanel.width }}
            suppressHydrationWarning
          >
            {rootsNav}
          </nav>
        </div>
        <PanelResizeHandle
          width={rootsPanel.width}
          onWidthChange={rootsPanel.setWidth}
          min={rootsPanel.min}
          max={rootsPanel.max}
          placement="after"
          label="Redimensionner les sources"
          showFrom="lg"
        />

        {rootsDrawerOpen && (
          <div className="absolute inset-0 z-[var(--z-drawer)] lg:hidden">
            <button
              type="button"
              className="absolute inset-0 bg-black/50 backdrop-blur-[2px]"
              aria-label="Fermer les sources"
              onClick={onCloseRootsDrawer}
            />
            <div className="glass-sidebar absolute inset-y-2 left-2 z-[1] flex w-[min(20rem,86vw)] flex-col overflow-hidden p-3">
              <p className="mb-2 px-2 text-xs font-medium uppercase tracking-wide text-muted">
                Sources
              </p>
              {rootsNav}
            </div>
          </div>
        )}

        <div className="flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden">
          <div
            className={cn(
              "shrink-0 border-b border-border-subtle",
              mobilePreviewFullscreen && "hidden lg:block"
            )}
          >
            {toolbar}
          </div>
          <div className="flex min-h-0 flex-1 overflow-hidden">
            <main
              className={cn(
                "flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden",
                mobilePreviewFullscreen && "hidden lg:flex"
              )}
            >
              {children}
            </main>

            {previewOpen && preview && (
              <>
                <PanelResizeHandle
                  width={effectivePreviewWidth}
                  onWidthChange={setPreviewWidth}
                  min={280}
                  max={640}
                  placement="before"
                  label="Redimensionner l'aperçu"
                  showFrom="lg"
                />
                <aside
                  className="hidden shrink-0 border-l border-border-subtle bg-surface lg:flex lg:flex-col"
                  style={{ width: effectivePreviewWidth }}
                >
                  {preview}
                </aside>
              </>
            )}
          </div>
        </div>

        {mobilePreviewFullscreen && preview && (
          <div className="absolute inset-0 z-[var(--z-modal)] flex flex-col lg:hidden">
            <div
              className="absolute inset-0 bg-[color-mix(in_srgb,var(--background)_82%,transparent)] backdrop-blur-[6px]"
              aria-hidden
            />
            <div className="glass relative z-10 flex mobile-chrome-header items-center justify-between px-2 safe-x">
              <span className="px-2 text-[15px] font-semibold tracking-[-0.02em]">
                Aperçu
              </span>
              <button
                type="button"
                className="inline-flex h-11 min-w-11 items-center justify-center rounded-[var(--radius-md)] px-3 text-sm text-muted hover:bg-surface-hover hover:text-foreground"
                onClick={onCloseMobilePreview}
              >
                Fermer
              </button>
            </div>
            <div className="relative z-10 min-h-0 flex-1 overflow-hidden">
              {preview}
            </div>
          </div>
        )}
      </div>

      {overlay}
    </div>
  );
}
