"use client";

import { useState } from "react";
import { SlidersHorizontal } from "lucide-react";
import { ModeSelector } from "@/components/chat/ModeSelector";
import { ModelSelector, type ModelOption } from "@/components/chat/ModelSelector";
import { ReasoningModeSelector } from "@/components/chat/ReasoningModeSelector";
import { WebSearchToggle } from "@/components/chat/WebSearchToggle";
import { ContextUsageIndicator } from "@/components/chat/ContextUsageIndicator";
import { MobileBottomSheet } from "@/components/ui/MobileBottomSheet";
import type { ChatMode } from "@/lib/agent/types";
import type { ContextSnapshot } from "@/lib/context/builder";
import type { RuntimeUsage } from "@/lib/runtime/types";
import { cn } from "@/lib/utils/cn";

interface ComposerToolbarProps {
  disabled?: boolean;
  chatMode?: ChatMode;
  onModeChange?: (mode: ChatMode) => void;
  models?: ModelOption[];
  selectedModel?: string;
  onModelChange?: (modelId: string) => void;
  modelsLoading?: boolean;
  modelSwitching?: boolean;
  modelSwitchMessage?: string;
  reasoningMode?: string | null;
  onReasoningChange?: (modeId: string) => void;
  webSearchEnabled?: boolean;
  onWebSearchChange?: (enabled: boolean) => void;
  contextSnapshot?: ContextSnapshot | null;
  contextLoading?: boolean;
  lastGenerationUsage?: RuntimeUsage | null;
}

export function ComposerToolbar({
  disabled,
  chatMode = "chat",
  onModeChange,
  models = [],
  selectedModel = "",
  onModelChange,
  modelsLoading,
  modelSwitching,
  modelSwitchMessage,
  reasoningMode,
  onReasoningChange,
  webSearchEnabled = true,
  onWebSearchChange,
  contextSnapshot,
  contextLoading,
  lastGenerationUsage,
}: ComposerToolbarProps) {
  const [optionsOpen, setOptionsOpen] = useState(false);

  const optionsBody = (
    <div className="flex flex-col gap-3 p-2">
      {onModeChange && (
        <div className="space-y-1.5">
          <p className="px-1 text-[10px] font-medium uppercase tracking-[0.06em] text-muted-foreground">
            Mode
          </p>
          <ModeSelector
            value={chatMode}
            disabled={disabled}
            onChange={onModeChange}
          />
        </div>
      )}
      {onModelChange && (
        <div className="space-y-1.5">
          <p className="px-1 text-[10px] font-medium uppercase tracking-[0.06em] text-muted-foreground">
            Modèle
          </p>
          <ModelSelector
            models={models}
            value={selectedModel}
            disabled={disabled}
            loading={modelsLoading}
            switching={modelSwitching}
            switchingLabel={modelSwitchMessage}
            onChange={onModelChange}
          />
        </div>
      )}
      {onReasoningChange && (
        <div className="space-y-1.5">
          <p className="px-1 text-[10px] font-medium uppercase tracking-[0.06em] text-muted-foreground">
            Raisonnement
          </p>
          <ReasoningModeSelector
            modelId={selectedModel}
            value={reasoningMode ?? null}
            disabled={disabled || !selectedModel}
            onChange={onReasoningChange}
          />
        </div>
      )}
      {onWebSearchChange && (
        <div className="space-y-1.5">
          <p className="px-1 text-[10px] font-medium uppercase tracking-[0.06em] text-muted-foreground">
            Web
          </p>
          <WebSearchToggle
            enabled={webSearchEnabled}
            disabled={disabled}
            onChange={onWebSearchChange}
          />
        </div>
      )}
      <div className="space-y-1.5 border-t border-border-subtle pt-3">
        <p className="px-1 text-[10px] font-medium uppercase tracking-[0.06em] text-muted-foreground">
          Contexte
        </p>
        <div className="px-1">
          <ContextUsageIndicator
            snapshot={contextSnapshot ?? null}
            lastGeneration={lastGenerationUsage}
            loading={contextLoading}
          />
        </div>
      </div>
    </div>
  );

  return (
    <>
      {/* Mobile: une rangée minimale */}
      <div className="flex items-center justify-between gap-2 border-t border-border-subtle pt-2 md:hidden">
        <button
          type="button"
          onClick={() => setOptionsOpen(true)}
          disabled={disabled}
          className={cn(
            "inline-flex min-h-9 items-center gap-1.5 rounded-[var(--radius-md)] px-2.5 py-1.5",
            "text-[12px] font-medium text-muted transition-colors",
            "hover:bg-surface-hover hover:text-foreground disabled:opacity-50"
          )}
          aria-label="Options du message"
        >
          <SlidersHorizontal className="h-3.5 w-3.5" />
          Options
        </button>
        <ContextUsageIndicator
          snapshot={contextSnapshot ?? null}
          lastGeneration={lastGenerationUsage}
          loading={contextLoading}
        />
      </div>

      {/* Desktop: toolbar complète */}
      <div className="hidden border-t border-border-subtle pt-2 md:block">
        <div className="flex items-center justify-between gap-2">
          <div className="flex min-w-0 flex-1 items-center gap-0.5">
            {onModeChange && (
              <ModeSelector
                value={chatMode}
                disabled={disabled}
                onChange={onModeChange}
              />
            )}
            {onModelChange && (
              <ModelSelector
                models={models}
                value={selectedModel}
                disabled={disabled}
                loading={modelsLoading}
                switching={modelSwitching}
                switchingLabel={modelSwitchMessage}
                onChange={onModelChange}
              />
            )}
            {onReasoningChange && (
              <ReasoningModeSelector
                modelId={selectedModel}
                value={reasoningMode ?? null}
                disabled={disabled || !selectedModel}
                onChange={onReasoningChange}
              />
            )}
            {onWebSearchChange && (
              <WebSearchToggle
                enabled={webSearchEnabled}
                disabled={disabled}
                onChange={onWebSearchChange}
              />
            )}
          </div>
          <ContextUsageIndicator
            snapshot={contextSnapshot ?? null}
            lastGeneration={lastGenerationUsage}
            loading={contextLoading}
          />
        </div>
      </div>

      <MobileBottomSheet
        open={optionsOpen}
        onClose={() => setOptionsOpen(false)}
        title="Options"
        description="Mode, modèle et outils"
      >
        {optionsBody}
      </MobileBottomSheet>
    </>
  );
}
