"use client";

import { useState } from "react";
import { RefreshCw, Brain, Pencil, MoreHorizontal } from "lucide-react";
import { MarkdownContent } from "@/components/chat/MarkdownContent";
import { SourceCitations } from "@/components/chat/SourceCitations";
import { MessageAttachments } from "@/components/chat/AttachmentPreview";
import { UserMessageEditor } from "@/components/chat/UserMessageEditor";
import { GenerationIndicator } from "@/components/chat/GenerationIndicator";
import { MemorySavedNotice } from "@/components/chat/MemorySavedNotice";
import { MailHandoffCard } from "@/components/mail/MailHandoffCard";
import type { MailHandoffInfo } from "@/components/mail/MailHandoffCard";
import { FilesHandoffCard } from "@/components/files/FilesHandoffCard";
import type { FilesHandoffInfo } from "@/components/files/FilesHandoffCard";
import {
  FilesMutationConfirmation,
  type FilesMutationPending,
} from "@/components/files/FilesMutationConfirmation";
import { CopyIconButton } from "@/components/ui/CopyIconButton";
import type { SavedMemoryItem } from "@/lib/memory/saved-memory";
import { IconButton } from "@/components/ui/IconButton";
import {
  MobileBottomSheet,
  MobileSheetAction,
} from "@/components/ui/MobileBottomSheet";
import { cn } from "@/lib/utils/cn";

interface MessageSource {
  id: string;
  title: string;
  domain: string;
  url: string;
  snippet: string | null;
}

interface MessageAttachment {
  id: string;
  filename: string;
  mimeType: string;
  sizeBytes: number;
  type: string;
}

export interface ChatMessageItem {
  id: string;
  role: string;
  content: string;
  streaming?: boolean;
  sources?: MessageSource[];
  attachments?: MessageAttachment[];
  savedMemories?: SavedMemoryItem[];
  mailHandoff?: MailHandoffInfo;
  filesHandoff?: FilesHandoffInfo;
  filesMutationPending?: FilesMutationPending;
}

interface MessageBubbleProps {
  message: ChatMessageItem;
  isEditing: boolean;
  isGenerating: boolean;
  canEdit: boolean;
  onEdit: () => void;
  onEditSubmit: (content: string) => void;
  onEditCancel: () => void;
  onRegenerate: () => void;
  onMemorize: () => void;
  onDeleteSavedMemory?: (memoryId: string) => Promise<void>;
  onFilesMutationDone?: (messageId: string) => void;
}

export function MessageBubble({
  message,
  isEditing,
  isGenerating,
  canEdit,
  onEdit,
  onEditSubmit,
  onEditCancel,
  onRegenerate,
  onMemorize,
  onDeleteSavedMemory,
  onFilesMutationDone,
}: MessageBubbleProps) {
  const isUser = message.role === "user";
  const [menuOpen, setMenuOpen] = useState(false);

  if (isUser) {
    return (
      <article className="group flex flex-col items-end">
        <div className="mb-1.5 flex w-full items-center justify-end gap-1">
          {/* Mobile: edit primaire + overflow */}
          <div className="flex items-center gap-0.5 md:hidden">
            {canEdit && (
              <IconButton
                size="sm"
                label="Modifier"
                onClick={onEdit}
                className="!h-8 !w-8 max-md:!h-8 max-md:!w-8"
              >
                <Pencil className="h-3.5 w-3.5" />
              </IconButton>
            )}
            <button
              type="button"
              className="inline-flex h-8 w-8 items-center justify-center rounded-[var(--radius-md)] text-muted hover:bg-surface-hover hover:text-foreground"
              aria-label="Plus d'actions"
              onClick={() => setMenuOpen(true)}
            >
              <MoreHorizontal className="h-4 w-4" />
            </button>
          </div>

          {/* Desktop: hover reveal */}
          <div className="hidden items-center gap-0.5 opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100 md:flex">
            <IconButton
              size="sm"
              label="Mémoriser"
              onClick={onMemorize}
              className="h-7 w-7"
            >
              <Brain className="h-3.5 w-3.5" />
            </IconButton>
            {canEdit && (
              <IconButton
                size="sm"
                label="Modifier"
                onClick={onEdit}
                className="h-7 w-7"
              >
                <Pencil className="h-3.5 w-3.5" />
              </IconButton>
            )}
          </div>
          <span className="text-xs font-medium text-muted-foreground">Vous</span>
        </div>

        {isEditing ? (
          <UserMessageEditor
            initialContent={message.content}
            attachments={message.attachments}
            disabled={isGenerating}
            onCancel={onEditCancel}
            onSubmit={onEditSubmit}
          />
        ) : (
          <div
            className={cn(
              "user-message-bubble w-full max-w-[min(calc(100%-0.5rem),36rem)] px-4 py-3 sm:max-w-[85%] md:max-w-[78%]"
            )}
          >
            <div className="min-w-0 whitespace-pre-wrap break-words text-[length:var(--text-base)] leading-relaxed text-foreground">
              {message.content}
            </div>
            {message.attachments && message.attachments.length > 0 && (
              <MessageAttachments attachments={message.attachments} />
            )}
          </div>
        )}

        <MobileBottomSheet
          open={menuOpen}
          onClose={() => setMenuOpen(false)}
          title="Message"
          description="Actions"
        >
          <ul className="space-y-0.5 p-1">
            <li>
              <MobileSheetAction
                label="Mémoriser"
                icon={<Brain className="h-4 w-4" />}
                onClick={() => {
                  onMemorize();
                  setMenuOpen(false);
                }}
              />
            </li>
            {canEdit && (
              <li>
                <MobileSheetAction
                  label="Modifier"
                  icon={<Pencil className="h-4 w-4" />}
                  onClick={() => {
                    onEdit();
                    setMenuOpen(false);
                  }}
                />
              </li>
            )}
          </ul>
        </MobileBottomSheet>
      </article>
    );
  }

  return (
    <article className="group">
      <div className="mb-1.5 flex items-center gap-2">
        <span className="text-xs font-medium text-muted-foreground">Assistant</span>
        {message.streaming && !message.content && (
          <GenerationIndicator />
        )}
        <div className="ml-auto flex items-center gap-0.5">
          {message.content ? (
            <CopyIconButton
              value={message.content}
              className="max-md:!opacity-100 md:opacity-0 md:group-hover:opacity-100 md:group-focus-within:opacity-100"
            />
          ) : null}

          {/* Mobile: regenerate in overflow */}
          {!message.streaming && (
            <>
              <button
                type="button"
                className="inline-flex h-8 w-8 items-center justify-center rounded-[var(--radius-md)] text-muted hover:bg-surface-hover hover:text-foreground md:hidden"
                aria-label="Plus d'actions"
                onClick={() => setMenuOpen(true)}
              >
                <MoreHorizontal className="h-4 w-4" />
              </button>
              <div className="hidden opacity-0 transition-opacity group-hover:opacity-100 group-focus-within:opacity-100 md:block">
                <IconButton
                  size="sm"
                  label="Régénérer"
                  onClick={onRegenerate}
                  className="h-7 w-7"
                >
                  <RefreshCw className="h-3.5 w-3.5" />
                </IconButton>
              </div>
            </>
          )}
        </div>
      </div>

      <div className="assistant-message min-w-0 overflow-x-hidden">
        {message.savedMemories &&
          message.savedMemories.length > 0 &&
          onDeleteSavedMemory && (
            <MemorySavedNotice
              memories={message.savedMemories}
              onDelete={onDeleteSavedMemory}
            />
          )}
        {message.mailHandoff && (
          <MailHandoffCard handoff={message.mailHandoff} />
        )}
        {message.filesHandoff && (
          <FilesHandoffCard handoff={message.filesHandoff} />
        )}
        {message.filesMutationPending && (
          <FilesMutationConfirmation
            proposals={[message.filesMutationPending]}
            onDone={() => onFilesMutationDone?.(message.id)}
          />
        )}
        {message.sources && message.sources.length > 0 && (
          <SourceCitations
            sources={message.sources.map((s) => ({
              title: s.title,
              url: s.url,
              domain: s.domain,
              snippet: s.snippet ?? "",
            }))}
          />
        )}
        {(message.content || message.streaming) && (
          <MarkdownContent content={message.content} streaming={message.streaming} />
        )}
      </div>

      <MobileBottomSheet
        open={menuOpen}
        onClose={() => setMenuOpen(false)}
        title="Réponse"
        description="Actions"
      >
        <ul className="space-y-0.5 p-1">
          <li>
            <MobileSheetAction
              label="Régénérer"
              icon={<RefreshCw className="h-4 w-4" />}
              onClick={() => {
                onRegenerate();
                setMenuOpen(false);
              }}
            />
          </li>
        </ul>
      </MobileBottomSheet>
    </article>
  );
}
