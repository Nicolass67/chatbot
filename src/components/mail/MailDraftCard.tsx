"use client";

import { useState } from "react";
import { Pencil, Send } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { DraftEditor } from "@/components/email/DraftEditor";
import { AttachmentGallery } from "@/components/attachments/AttachmentActionSheet";
import type { EmailDraftPreview } from "@/lib/email/draft/types";
import type { UpdateDraftInput } from "@/lib/email/email-client";

interface MailDraftCardProps {
  draft: EmailDraftPreview;
  disabled?: boolean;
  onSave: (patch: UpdateDraftInput) => Promise<void>;
  onDismiss: () => void;
  onPrepareSend: () => void;
}

export function MailDraftCard({
  draft,
  disabled,
  onSave,
  onDismiss,
  onPrepareSend,
}: MailDraftCardProps) {
  const [editing, setEditing] = useState(false);
  const attachments = draft.attachments ?? [];

  if (editing) {
    return (
      <div className="rounded-[var(--radius-md)] border border-border-subtle bg-surface p-3">
        <p className="mb-2 text-xs font-medium text-accent">Brouillon — édition</p>
        <DraftEditor
          draft={draft}
          disabled={disabled}
          onSave={async (patch) => {
            await onSave(patch);
            setEditing(false);
          }}
          onCancel={() => setEditing(false)}
        />
      </div>
    );
  }

  const toLabel =
    draft.to.length > 0 ? draft.to.join(", ") : "(destinataire à renseigner)";

  return (
    <div className="rounded-[var(--radius-md)] border border-border-subtle bg-surface p-3">
      <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-accent">
        Brouillon email
      </p>
      <dl className="mb-3 space-y-1.5 text-sm">
        <div>
          <dt className="text-[11px] font-medium text-muted-foreground">À</dt>
          <dd className="text-foreground">{toLabel}</dd>
        </div>
        <div>
          <dt className="text-[11px] font-medium text-muted-foreground">Objet</dt>
          <dd className="text-foreground">{draft.subject || "(sans objet)"}</dd>
        </div>
        <div>
          <dt className="text-[11px] font-medium text-muted-foreground">Message</dt>
          <dd className="whitespace-pre-wrap break-words text-muted-foreground">
            {draft.bodyText}
          </dd>
        </div>
        {attachments.length > 0 && (
          <div>
            <dt className="mb-1.5 text-[11px] font-medium text-muted-foreground">
              Pièces jointes
            </dt>
            <dd>
              <AttachmentGallery
                className="mt-0"
                attachments={attachments.map((att) => ({
                  id: att.id,
                  filename: att.filename,
                  mimeType: att.mimeType,
                  sizeBytes: att.sizeBytes,
                  url: `/api/attachments/${att.id}`,
                }))}
              />
            </dd>
          </div>
        )}
      </dl>
      <div className="flex flex-wrap gap-2">
        <Button
          variant="primary"
          size="sm"
          disabled={disabled || draft.to.length === 0}
          onClick={onPrepareSend}
        >
          <Send className="h-3.5 w-3.5" />
          Envoyer
        </Button>
        <Button
          variant="secondary"
          size="sm"
          disabled={disabled}
          onClick={() => setEditing(true)}
        >
          <Pencil className="h-3.5 w-3.5" />
          Modifier
        </Button>
        <Button variant="ghost" size="sm" disabled={disabled} onClick={onDismiss}>
          Fermer
        </Button>
      </div>
      {draft.to.length === 0 && (
        <p className="mt-2 text-xs text-amber-600">
          Indiquez un destinataire via « Modifier » ou demandez « envoie à mon adresse ».
        </p>
      )}
    </div>
  );
}
