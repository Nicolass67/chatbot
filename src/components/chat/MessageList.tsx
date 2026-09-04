"use client";

import { MessageBubble, type ChatMessageItem } from "@/components/chat/MessageBubble";
import { ChatEmptyState } from "@/components/chat/ChatEmptyState";
import { AgentStatusBar } from "@/components/chat/AgentStatusBar";
import { AgentPlanPanel } from "@/components/chat/AgentPlanPanel";
import { AgentSummary } from "@/components/chat/AgentSummary";
import { WebSearchActivity, type WebSearchPhase } from "@/components/chat/WebSearchActivity";
import { ToolStatus } from "@/components/chat/ToolStatus";
import { GenerationIndicator } from "@/components/chat/GenerationIndicator";
import type { AgentUiState } from "@/components/chat/agent-ui-state";
import type { ChatMode } from "@/lib/agent/types";
import { canStartEditingMessage } from "@/components/chat/user-message-edit";

interface MessageListProps {
  messages: ChatMessageItem[];
  chatMode: ChatMode;
  isGenerating: boolean;
  editingMessageId: string | null;
  agentUi: AgentUiState;
  webSearchActivity: {
    phase: WebSearchPhase;
    query?: string;
    sourceCount?: number;
  };
  toolState: {
    status: "idle" | "running" | "done";
    tool?: string;
    summary?: string;
    sourceCount?: number;
  };
  onEdit: (messageId: string) => void;
  onEditSubmit: (messageId: string, content: string) => void;
  onEditCancel: () => void;
  onRegenerate: () => void;
  onMemorize: (messageId: string) => void;
  onDeleteSavedMemory: (messageId: string, memoryId: string) => Promise<void>;
  onFilesMutationDone?: (messageId: string) => void;
  bottomRef: React.RefObject<HTMLDivElement | null>;
}

export function MessageList({
  messages,
  chatMode,
  isGenerating,
  editingMessageId,
  agentUi,
  webSearchActivity,
  toolState,
  onEdit,
  onEditSubmit,
  onEditCancel,
  onRegenerate,
  onMemorize,
  onDeleteSavedMemory,
  onFilesMutationDone,
  bottomRef,
}: MessageListProps) {
  const hasStreamingAssistant = messages.some(
    (m) => m.role === "assistant" && m.streaming
  );

  return (
    <div className="reading-column space-y-7 px-4 py-5 md:px-5 md:py-6">
      {messages.length === 0 && !isGenerating && (
        <ChatEmptyState chatMode={chatMode} />
      )}

      {messages.map((msg) => (
        <MessageBubble
          key={msg.id}
          message={msg}
          isEditing={editingMessageId === msg.id}
          isGenerating={isGenerating}
          canEdit={canStartEditingMessage(msg, isGenerating)}
          onEdit={() => onEdit(msg.id)}
          onEditSubmit={(content) => onEditSubmit(msg.id, content)}
          onEditCancel={onEditCancel}
          onRegenerate={onRegenerate}
          onMemorize={() => onMemorize(msg.id)}
          onDeleteSavedMemory={(memoryId) => onDeleteSavedMemory(msg.id, memoryId)}
          onFilesMutationDone={onFilesMutationDone}
        />
      ))}

      {chatMode === "agent" && (agentUi.plan || agentUi.phase) && (
        <div className="space-y-3">
          {isGenerating && agentUi.phase && (
            <AgentStatusBar
              phase={agentUi.phase}
              stepIndex={agentUi.stepIndex}
              totalSteps={agentUi.totalSteps}
              currentStepTitle={agentUi.currentStepTitle}
            />
          )}
          {agentUi.plan && <AgentPlanPanel plan={agentUi.plan} />}
          {!isGenerating && agentUi.summaryStats && (
            <AgentSummary
              stats={agentUi.summaryStats}
              stopReason={agentUi.stopReason}
              runOutcome={agentUi.runOutcome}
            />
          )}
        </div>
      )}

      {chatMode !== "agent" && webSearchActivity.phase !== "idle" && (
        <div className="space-y-2">
          <span className="text-xs font-medium text-muted-foreground">Assistant</span>
          <WebSearchActivity
            phase={webSearchActivity.phase}
            query={webSearchActivity.query}
            sourceCount={webSearchActivity.sourceCount}
          />
        </div>
      )}

      {isGenerating &&
        toolState.status !== "idle" &&
        toolState.tool !== "web_search" && (
          <ToolStatus {...toolState} />
        )}

      {isGenerating &&
        toolState.status === "idle" &&
        webSearchActivity.phase === "idle" &&
        !hasStreamingAssistant && (
          <GenerationIndicator />
        )}

      <div ref={bottomRef} aria-hidden />
    </div>
  );
}
