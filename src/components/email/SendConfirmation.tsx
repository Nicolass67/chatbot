"use client";

import { useEffect, useState } from "react";
import { AlertTriangle, Mail, Send } from "lucide-react";
import { Button } from "@/components/ui/Button";
import type { EmailDraftPreview } from "@/lib/email/draft/types";
import type { SendProposalResponse } from "@/lib/email/email-client";
import { cn } from "@/lib/utils/cn";

interface SendConfirmationProps {
  draft: EmailDraftPreview;
  proposal: SendProposalResponse;
  conversationId: string;
  disabled?: boolean;
  onConfirm: (
    actionId: string,
    confirmationToken: string
  ) => Promise<void>;
  onCancel: (actionId: string) => Promise<void>;
  onDismiss: () => void;
  className?: string;
}

function formatExpiresAt(expiresAt: string): string {
  const date = new Date(expiresAt);
  if (Number.isNaN(date.getTime())) return expiresAt;
  return date.toLocaleTimeString("fr-FR", {
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function SendConfirmation({
  draft,
  proposal,
  conversationId,
  disabled,
  onConfirm,
  onCancel,
  onDismiss,
  className,
}: SendConfirmationProps) {
  const [confirming, setConfirming] = useState(false);
  const [cancelling, setCancelling] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expired, setExpired] = useState(false);

  useEffect(() => {
    const ms = new Date(proposal.expiresAt).getTime() - Date.now();
    if (ms <= 0) {
      setExpired(true);
      return;
    }
    const timer = window.setTimeout(() => setExpired(true), ms);
    return () => window.clearTimeout(timer);
  }, [proposal.expiresAt]);

  const handleConfirm = async () => {
    setConfirming(true);
    setError(null);
    try {
      await onConfirm(proposal.actionId, proposal.confirmationToken);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Échec de l'envoi");
    } finally {
      setConfirming(false);
    }
  };

  const handleCancel = async () => {
    setCancelling(true);
    setError(null);
    try {
      await onCancel(proposal.actionId);
      onDismiss();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Échec de l'annulation");
    } finally {
      setCancelling(false);
    }
  };

  return (
    <div
      className={cn(
        "rounded-lg border border-warning/40 bg-warning-muted/30 px-3 py-3",
        className
      )}
    >
      <div className="mb-2 flex items-start gap-2">
        <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
        <div className="min-w-0 flex-1">
          <p className="text-xs font-medium text-foreground">
            Confirmer l&apos;envoi de cet email ?
          </p>
          <p className="mt-1 text-[11px] text-muted-foreground">
            Cette action enverra le message via Gmail. Vérifiez le contenu avant
            de confirmer.
          </p>
        </div>
      </div>

      <div className="mb-3 rounded-md border border-border-subtle bg-surface/80 px-3 py-2 text-xs">
        <div className="flex items-center gap-1.5 text-muted-foreground">
          <Mail className="h-3.5 w-3.5" />
          <span className="truncate">{draft.to.join(", ")}</span>
        </div>
        <p className="mt-1 font-medium text-foreground">{draft.subject}</p>
        <p className="mt-1 whitespace-pre-wrap break-words text-muted-foreground">
          {draft.bodyText}
        </p>
        {(draft.attachments?.length ?? 0) > 0 && (
          <p className="mt-1.5 text-[11px] text-foreground">
            {draft.attachments!.length} pièce(s) jointe(s) :{" "}
            {draft.attachments!.map((a) => a.filename).join(", ")}
          </p>
        )}
      </div>

      <p className="mb-2 text-[11px] text-muted-foreground">
        Conversation : {conversationId.slice(0, 8)}… · Expire à{" "}
        {formatExpiresAt(proposal.expiresAt)}
        {expired ? " (expiré)" : ""}
      </p>

      {error && (
        <p className="mb-2 text-xs text-error" role="alert">
          {error}
        </p>
      )}

      <div className="flex flex-wrap gap-2">
        <Button
          type="button"
          variant="primary"
          size="sm"
          loading={confirming}
          disabled={disabled || cancelling || expired}
          onClick={() => void handleConfirm()}
        >
          <Send className="h-3.5 w-3.5" />
          Confirmer l&apos;envoi
        </Button>
        <Button
          type="button"
          variant="secondary"
          size="sm"
          loading={cancelling}
          disabled={disabled || confirming}
          onClick={() => void handleCancel()}
        >
          Annuler
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          disabled={confirming || cancelling}
          onClick={onDismiss}
        >
          Fermer
        </Button>
      </div>
    </div>
  );
}
