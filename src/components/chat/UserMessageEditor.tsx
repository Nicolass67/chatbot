"use client";

import { useEffect, useRef, useState } from "react";
import { canSubmitEditedMessage } from "@/lib/agent/edit-message-utils";
import { handleEditTextareaKeyDown } from "@/components/chat/user-message-edit";
import { MessageAttachments } from "@/components/chat/AttachmentPreview";
import { Button } from "@/components/ui/Button";

interface UserMessageEditorProps {
  initialContent: string;
  attachments?: Array<{
    id: string;
    filename: string;
    mimeType: string;
    sizeBytes: number;
    type: string;
  }>;
  disabled?: boolean;
  onCancel: () => void;
  onSubmit: (content: string) => void;
}

export function UserMessageEditor({
  initialContent,
  attachments = [],
  disabled,
  onCancel,
  onSubmit,
}: UserMessageEditorProps) {
  const [draft, setDraft] = useState(initialContent);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    setDraft(initialContent);
  }, [initialContent]);

  useEffect(() => {
    const ta = textareaRef.current;
    if (!ta) return;
    ta.focus();
    ta.setSelectionRange(ta.value.length, ta.value.length);
    ta.style.height = "auto";
    ta.style.height = `${Math.min(ta.scrollHeight, 320)}px`;
  }, [initialContent]);

  useEffect(() => {
    const ta = textareaRef.current;
    if (!ta) return;
    ta.style.height = "auto";
    ta.style.height = `${Math.min(ta.scrollHeight, 320)}px`;
  }, [draft]);

  const canSubmit = canSubmitEditedMessage(draft, attachments.length) && !disabled;

  const submit = () => {
    if (!canSubmit) return;
    onSubmit(draft.trim());
  };

  return (
    <div className="user-message-bubble w-full max-w-[min(calc(100%-0.5rem),36rem)] px-3 py-3 sm:max-w-[85%] md:max-w-[78%]">
      <textarea
        ref={textareaRef}
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onKeyDown={(e) => handleEditTextareaKeyDown(e, submit)}
        disabled={disabled}
        rows={3}
        className="max-h-80 min-h-[72px] w-full resize-none bg-transparent text-[length:var(--text-base)] leading-relaxed text-foreground outline-none focus:outline-none focus-visible:outline-none"
        aria-label="Modifier le message"
      />
      {attachments.length > 0 && (
        <div className="mt-2 border-t border-border-subtle pt-2">
          <MessageAttachments attachments={attachments} />
        </div>
      )}
      <div className="mt-3 flex items-center justify-end gap-2">
        <Button variant="ghost" size="sm" onClick={onCancel} disabled={disabled}>
          Annuler
        </Button>
        <Button variant="primary" size="sm" onClick={submit} disabled={!canSubmit}>
          Envoyer
        </Button>
      </div>
    </div>
  );
}
