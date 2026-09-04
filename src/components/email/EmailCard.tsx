"use client";

import { useEffect, useState } from "react";
import { Check, Mail, Pencil, Send } from "lucide-react";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { DraftEditor } from "@/components/email/DraftEditor";
import { SendConfirmation } from "@/components/email/SendConfirmation";
import type { EmailDraftPreview } from "@/lib/email/draft/types";
import {
  emailDraftStatusLabel,
  emailDraftStatusVariant,
} from "@/lib/email/draft-labels";
import {
  confirmEmailSend,
  cancelEmailSendAction,
  proposeEmailSend,
  updateEmailDraft,
  validateEmailDraft,
  type SendProposalResponse,
} from "@/lib/email/email-client";
import { cn } from "@/lib/utils/cn";

interface EmailCardProps {
  draft: EmailDraftPreview;
  conversationId: string;
  disabled?: boolean;
  hasPendingConfirmation?: boolean;
  onDraftChange: (draft: EmailDraftPreview) => void;
  onSent?: (draftId: string) => void;
  onSendProposed?: (draftId: string) => void;
  className?: string;
}

export function EmailCard({
  draft: initialDraft,
  conversationId,
  disabled,
  hasPendingConfirmation,
  onDraftChange,
  onSent,
  onSendProposed,
  className,
}: EmailCardProps) {
  const [draft, setDraft] = useState(initialDraft);
  const [editing, setEditing] = useState(false);
  const [proposal, setProposal] = useState<SendProposalResponse | null>(null);
  const [loading, setLoading] = useState<"validate" | "send" | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setDraft(initialDraft);
  }, [initialDraft]);

  const updateDraft = (next: EmailDraftPreview) => {
    setDraft(next);
    onDraftChange(next);
  };

  const handleSave = async (patch: Parameters<typeof updateEmailDraft>[1]) => {
    const updated = await updateEmailDraft(draft.draftId, patch);
    updateDraft(updated);
    setEditing(false);
    setProposal(null);
  };

  const handleValidate = async () => {
    setLoading("validate");
    setError(null);
    try {
      const validated = await validateEmailDraft(draft.draftId);
      updateDraft(validated);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Validation impossible");
    } finally {
      setLoading(null);
    }
  };

  const handleProposeSend = async () => {
    setLoading("send");
    setError(null);
    try {
      const nextProposal = await proposeEmailSend(draft.draftId);
      setProposal(nextProposal);
      updateDraft(nextProposal.draft);
      onSendProposed?.(draft.draftId);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Impossible de préparer l'envoi");
    } finally {
      setLoading(null);
    }
  };

  const handleConfirmSend = async (
    actionId: string,
    confirmationToken: string
  ) => {
    await confirmEmailSend(actionId, {
      confirmationToken,
      conversationId,
    });
    updateDraft({ ...draft, status: "sent" });
    setProposal(null);
    onSent?.(draft.draftId);
  };

  const handleCancelSend = async (actionId: string) => {
    await cancelEmailSendAction(actionId);
    setProposal(null);
  };

  const isLocked =
    draft.status === "sent" || draft.status === "cancelled" || disabled;

  return (
    <div
      className={cn(
        "rounded-[var(--radius-lg)] border border-border-subtle bg-surface p-3.5",
        className
      )}
    >
      <div className="mb-3 flex flex-wrap items-start justify-between gap-2">
        <div className="flex items-center gap-2">
          <Mail className="h-4 w-4 text-accent" />
          <span className="text-sm font-medium text-foreground">
            Brouillon email
          </span>
          <Badge variant={emailDraftStatusVariant(draft.status)}>
            {emailDraftStatusLabel(draft.status)}
          </Badge>
        </div>
        {hasPendingConfirmation && !proposal && draft.status === "validated" && (
          <Badge variant="warning">Confirmation en attente</Badge>
        )}
      </div>

      {editing ? (
        <DraftEditor
          draft={draft}
          disabled={isLocked}
          onSave={handleSave}
          onCancel={() => setEditing(false)}
        />
      ) : (
        <>
          <dl className="space-y-2 text-xs">
            <div>
              <dt className="text-muted-foreground">À</dt>
              <dd className="text-foreground">{draft.to.join(", ") || "—"}</dd>
            </div>
            {draft.cc.length > 0 && (
              <div>
                <dt className="text-muted-foreground">Cc</dt>
                <dd className="text-foreground">{draft.cc.join(", ")}</dd>
              </div>
            )}
            <div>
              <dt className="text-muted-foreground">Objet</dt>
              <dd className="font-medium text-foreground">{draft.subject || "—"}</dd>
            </div>
            <div>
              <dt className="text-muted-foreground">Message</dt>
              <dd className="whitespace-pre-wrap break-words text-foreground/90">
                {draft.bodyText}
              </dd>
            </div>
          </dl>

          {proposal && (
            <SendConfirmation
              className="mt-3"
              draft={draft}
              proposal={proposal}
              conversationId={conversationId}
              disabled={isLocked}
              onConfirm={handleConfirmSend}
              onCancel={handleCancelSend}
              onDismiss={() => setProposal(null)}
            />
          )}

          {error && (
            <p className="mt-2 text-xs text-error" role="alert">
              {error}
            </p>
          )}

          {!isLocked && !proposal && (
            <div className="mt-3 flex flex-wrap gap-2">
              <Button
                type="button"
                variant="secondary"
                size="sm"
                onClick={() => setEditing(true)}
              >
                <Pencil className="h-3.5 w-3.5" />
                Modifier
              </Button>
              {draft.status === "draft" && (
                <Button
                  type="button"
                  variant="primary"
                  size="sm"
                  loading={loading === "validate"}
                  onClick={() => void handleValidate()}
                >
                  <Check className="h-3.5 w-3.5" />
                  Valider
                </Button>
              )}
              {draft.status === "validated" && (
                <Button
                  type="button"
                  variant="primary"
                  size="sm"
                  loading={loading === "send"}
                  onClick={() => void handleProposeSend()}
                >
                  <Send className="h-3.5 w-3.5" />
                  {hasPendingConfirmation ? "Continuer l'envoi" : "Envoyer"}
                </Button>
              )}
            </div>
          )}

          {draft.status === "sent" && (
            <p className="mt-3 text-xs text-success">
              Email envoyé via Gmail.
            </p>
          )}
        </>
      )}
    </div>
  );
}
