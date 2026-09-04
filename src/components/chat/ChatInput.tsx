"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { ArrowUp, Paperclip, Square } from "lucide-react";
import type { PendingAttachment } from "@/components/chat/AttachmentPreview";
import { AttachmentPreviewList } from "@/components/chat/AttachmentPreview";
import { ComposerToolbar } from "@/components/chat/ComposerToolbar";
import type { ModelOption } from "@/components/chat/ModelSelector";
import type { ChatMode } from "@/lib/agent/types";
import type { ContextSnapshot } from "@/lib/context/builder";
import type { RuntimeUsage } from "@/lib/runtime/types";
import { IconButton } from "@/components/ui/IconButton";
import { cn } from "@/lib/utils/cn";

interface ChatInputProps {
  conversationId: string;
  onEnsureConversationId?: () => Promise<string>;
  onSend: (message: string, attachmentIds: string[]) => void;
  onStop?: () => void;
  disabled?: boolean;
  isGenerating?: boolean;
  placeholder?: string;
  contextSnapshot?: ContextSnapshot | null;
  contextLoading?: boolean;
  lastGenerationUsage?: RuntimeUsage | null;
  onAttachmentsChange?: (attachmentIds: string[]) => void;
  models?: ModelOption[];
  selectedModel?: string;
  onModelChange?: (modelId: string) => void;
  modelsLoading?: boolean;
  modelSwitching?: boolean;
  modelSwitchMessage?: string;
  reasoningMode?: string | null;
  onReasoningChange?: (modeId: string) => void;
  chatMode?: ChatMode;
  onModeChange?: (mode: ChatMode) => void;
  webSearchEnabled?: boolean;
  onWebSearchChange?: (enabled: boolean) => void;
}

export function ChatInput({
  conversationId,
  onEnsureConversationId,
  onSend,
  onStop,
  disabled,
  isGenerating,
  placeholder = "Envoyer un message…",
  contextSnapshot,
  contextLoading,
  lastGenerationUsage,
  onAttachmentsChange,
  models = [],
  selectedModel = "",
  onModelChange,
  modelsLoading,
  modelSwitching,
  modelSwitchMessage,
  reasoningMode,
  onReasoningChange,
  chatMode = "chat",
  onModeChange,
  webSearchEnabled = true,
  onWebSearchChange,
}: ChatInputProps) {
  const [value, setValue] = useState("");
  const [attachments, setAttachments] = useState<PendingAttachment[]>([]);
  const [dragOver, setDragOver] = useState(false);
  const [focused, setFocused] = useState(false);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const lastAttachmentIdsRef = useRef("");
  const lastComposerActionRef = useRef<"text" | "attachment" | null>(null);

  useEffect(() => {
    if (!onAttachmentsChange) return;
    const ids = attachments
      .filter((a) => !a.uploading && !a.error && !a.id.startsWith("temp-"))
      .map((a) => a.id);
    const key = ids.join("\0");
    if (key === lastAttachmentIdsRef.current) return;
    lastAttachmentIdsRef.current = key;
    onAttachmentsChange(ids);
  }, [attachments, onAttachmentsChange]);

  useEffect(() => {
    const ta = textareaRef.current;
    if (ta) {
      ta.style.height = "auto";
      ta.style.height = `${Math.min(ta.scrollHeight, 200)}px`;
    }
  }, [value]);

  const uploadFile = useCallback(
    async (file: File, previewUrl?: string) => {
      const tempId = `temp-${Date.now()}-${Math.random()}`;
      setAttachments((prev) => [
        ...prev,
        {
          id: tempId,
          filename: file.name,
          mimeType: file.type,
          sizeBytes: file.size,
          type: file.type.startsWith("image/") ? "image" : "document",
          previewUrl,
          uploading: true,
        },
      ]);
      lastComposerActionRef.current = "attachment";

      let convId = conversationId;
      if (convId === "new" && onEnsureConversationId) {
        convId = await onEnsureConversationId();
      }

      const form = new FormData();
      form.append("file", file);
      form.append("conversationId", convId);

      try {
        const res = await fetch("/api/attachments/upload", {
          method: "POST",
          body: form,
        });
        const data = (await res.json()) as {
          error?: string;
          attachment?: {
            id: string;
            filename: string;
            mimeType: string;
            sizeBytes: number;
          };
        };
        if (!res.ok) {
          setAttachments((prev) =>
            prev.map((a) =>
              a.id === tempId
                ? { ...a, uploading: false, error: data.error ?? "Échec upload" }
                : a
            )
          );
          return;
        }

        const att = data.attachment as {
          id: string;
          filename: string;
          mimeType: string;
          sizeBytes: number;
          type: "image" | "document";
        };

        setAttachments((prev) =>
          prev.map((a) =>
            a.id === tempId
              ? {
                  id: att.id,
                  filename: att.filename,
                  mimeType: att.mimeType,
                  sizeBytes: att.sizeBytes,
                  type: att.type,
                  previewUrl,
                  uploading: false,
                }
              : a
          )
        );
      } catch {
        setAttachments((prev) =>
          prev.map((a) =>
            a.id === tempId
              ? { ...a, uploading: false, error: "Erreur réseau" }
              : a
          )
        );
      }
    },
    [conversationId, onEnsureConversationId]
  );

  const handleFiles = useCallback(
    async (files: FileList | File[]) => {
      for (const file of Array.from(files)) {
        const previewUrl = file.type.startsWith("image/")
          ? URL.createObjectURL(file)
          : undefined;
        await uploadFile(file, previewUrl);
      }
    },
    [uploadFile]
  );

  const handlePaste = (e: React.ClipboardEvent) => {
    const items = e.clipboardData.items;
    const imageFiles: File[] = [];
    for (const item of items) {
      if (item.type.startsWith("image/")) {
        const file = item.getAsFile();
        if (file) imageFiles.push(file);
      }
    }
    if (imageFiles.length > 0) {
      e.preventDefault();
      void handleFiles(imageFiles);
    }
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setDragOver(false);
    if (e.dataTransfer.files.length > 0) {
      void handleFiles(e.dataTransfer.files);
    }
  };

  const removeAttachment = useCallback(async (id: string) => {
    setAttachments((prev) => {
      const removed = prev.find((a) => a.id === id);
      if (removed?.previewUrl?.startsWith("blob:")) {
        URL.revokeObjectURL(removed.previewUrl);
      }
      return prev.filter((a) => a.id !== id);
    });
    if (!id.startsWith("temp-")) {
      await fetch(`/api/attachments/${id}`, { method: "DELETE" });
    }
  }, []);

  const undoLastAttachment = useCallback(() => {
    setAttachments((prev) => {
      const last = prev[prev.length - 1];
      if (!last) return prev;
      if (last.previewUrl?.startsWith("blob:")) {
        URL.revokeObjectURL(last.previewUrl);
      }
      if (!last.id.startsWith("temp-")) {
        void fetch(`/api/attachments/${last.id}`, { method: "DELETE" });
      }
      lastComposerActionRef.current = prev.length > 1 ? "attachment" : null;
      return prev.slice(0, -1);
    });
  }, []);

  const submit = () => {
    const trimmed = value.trim();
    const readyIds = attachments
      .filter((a) => !a.uploading && !a.error && !a.id.startsWith("temp-"))
      .map((a) => a.id);
    if ((!trimmed && readyIds.length === 0) || disabled || isGenerating) return;
    if (attachments.some((a) => a.uploading)) return;

    onSend(trimmed, readyIds);
    setValue("");
    setAttachments([]);
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if ((e.ctrlKey || e.metaKey) && e.key === "z" && !e.shiftKey) {
      if (
        attachments.length > 0 &&
        lastComposerActionRef.current === "attachment"
      ) {
        e.preventDefault();
        undoLastAttachment();
        return;
      }
    }
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      submit();
    }
  };

  const hasUploading = attachments.some((a) => a.uploading);
  const readyCount = attachments.filter(
    (a) => !a.uploading && !a.error && !a.id.startsWith("temp-")
  ).length;
  const canSend =
    (value.trim().length > 0 || readyCount > 0) &&
    !disabled &&
    !hasUploading &&
    !modelSwitching;

  const controlsDisabled = disabled || isGenerating;
  const [keyboardInset, setKeyboardInset] = useState(0);

  useEffect(() => {
    const vv = window.visualViewport;
    if (!vv) return;

    const update = () => {
      const inset = Math.max(0, window.innerHeight - vv.height - vv.offsetTop);
      setKeyboardInset(inset > 40 ? inset : 0);
    };

    update();
    vv.addEventListener("resize", update);
    vv.addEventListener("scroll", update);
    return () => {
      vv.removeEventListener("resize", update);
      vv.removeEventListener("scroll", update);
    };
  }, []);

  return (
    <div
      className="shrink-0 px-3 pt-2 pb-[max(1.25rem,env(safe-area-inset-bottom))] md:px-4 md:pb-[max(1.5rem,env(safe-area-inset-bottom))]"
      style={keyboardInset > 0 ? { paddingBottom: keyboardInset } : undefined}
      onDragOver={(e) => {
        e.preventDefault();
        setDragOver(true);
      }}
      onDragLeave={() => setDragOver(false)}
      onDrop={handleDrop}
    >
      <div
        className={cn(
          "composer-column glass-thick rounded-[var(--radius-2xl)] border p-1.5 transition-[border-color,box-shadow] duration-[var(--duration-normal)]",
          dragOver && "border-accent bg-accent-subtle",
          focused && !dragOver && "border-[color:var(--glass-border)]",
          !focused && !dragOver && "border-[color:var(--glass-border-soft)]"
        )}
      >
        <AttachmentPreviewList items={attachments} onRemove={removeAttachment} />

        <div className="flex items-end gap-1.5 px-1">
          <input
            ref={fileInputRef}
            type="file"
            multiple
            accept="image/jpeg,image/png,image/webp,.pdf,.docx,.txt,.md,.markdown,.csv,.json,.xlsx"
            className="hidden"
            onChange={(e) => {
              if (e.target.files) void handleFiles(e.target.files);
              e.target.value = "";
            }}
          />
          <IconButton
            size="lg"
            variant="ghost"
            label="Joindre un fichier"
            disabled={controlsDisabled}
            onClick={() => fileInputRef.current?.click()}
            className="mb-0.5"
          >
            <Paperclip className="h-5 w-5" />
          </IconButton>

          <textarea
            ref={textareaRef}
            value={value}
            onChange={(e) => {
              lastComposerActionRef.current = "text";
              setValue(e.target.value);
            }}
            onKeyDown={handleKeyDown}
            onPaste={handlePaste}
            onFocus={() => setFocused(true)}
            onBlur={() => setFocused(false)}
            placeholder={placeholder}
            disabled={disabled}
            rows={1}
            aria-label="Message"
            className="max-h-[200px] min-h-[44px] flex-1 resize-none bg-transparent px-1 py-2.5 text-base leading-relaxed text-foreground outline-none placeholder:text-muted focus:outline-none focus-visible:outline-none"
          />

          {isGenerating ? (
            <IconButton
              size="lg"
              variant="danger"
              label="Arrêter la génération"
              onClick={onStop}
              className="mb-0.5"
            >
              <Square className="h-4 w-4 fill-current" />
            </IconButton>
          ) : (
            <IconButton
              size="lg"
              variant={canSend ? "primary" : "subtle"}
              label="Envoyer"
              disabled={!canSend}
              onClick={submit}
              className="mb-0.5"
            >
              <ArrowUp className="h-5 w-5" />
            </IconButton>
          )}
        </div>

        <div className="px-1">
          <ComposerToolbar
            disabled={controlsDisabled}
            chatMode={chatMode}
            onModeChange={onModeChange}
            models={models}
            selectedModel={selectedModel}
            onModelChange={onModelChange}
            modelsLoading={modelsLoading}
            modelSwitching={modelSwitching}
            modelSwitchMessage={modelSwitchMessage}
            reasoningMode={reasoningMode}
            onReasoningChange={onReasoningChange}
            webSearchEnabled={webSearchEnabled}
            onWebSearchChange={onWebSearchChange}
            contextSnapshot={contextSnapshot}
            contextLoading={contextLoading}
            lastGenerationUsage={lastGenerationUsage}
          />
        </div>
      </div>
    </div>
  );
}
