"use client";

import { useState } from "react";
import { Reply, Trash2, Lightbulb } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { DraftEditor } from "@/components/email/DraftEditor";
import { SendConfirmation } from "@/components/email/SendConfirmation";
import { TrashConfirmation } from "@/components/mail/TrashConfirmation";
import type { EmailDraftPreview } from "@/lib/email/draft/types";
import type { SendProposalResponse } from "@/lib/email/email-client";
import type { ProposeTrashEmailResult } from "@/lib/email/trash/types";
import type { MailThread } from "@/lib/mail/mail-client";
import {
  cancelEmailSend,
  confirmEmailSend,
  proposeEmailSend,
  suggestMailReply,
  summarizeMailThread,
  validateEmailDraft,
} from "@/lib/mail/mail-client";
import type { UpdateDraftInput } from "@/lib/email/email-client";

interface MailAiPanelProps {
  thread: MailThread;
  selectedMessageId: string;
  onTrashConfirmed: (messageId: string) => void;
  onTrashFailed: (messageId: string) => void;
}

export function MailAiPanel({
  thread,
  selectedMessageId,
  onTrashConfirmed,
  onTrashFailed,
}: MailAiPanelProps) {
  const [summary, setSummary] = useState<string | null>(null);
  const [loadingSummary, setLoadingSummary] = useState(false);
  const [draft, setDraft] = useState<EmailDraftPreview | null>(null);
  const [sendProposal, setSendProposal] = useState<SendProposalResponse | null>(
    null
  );
  const [trashProposal, setTrashProposal] =
    useState<ProposeTrashEmailResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSummarize = async () => {
    setLoadingSummary(true);
    setError(null);
    try {
      const text = await summarizeMailThread(thread.id);
      setSummary(text);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Échec du résumé");
    } finally {
      setLoadingSummary(false);
    }
  };

  const handleSuggestReply = async () => {
    setBusy(true);
    setError(null);
    try {
      const result = await suggestMailReply({ threadId: thread.id });
      setDraft(result.draft);
      setSendProposal(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Échec de la suggestion");
    } finally {
      setBusy(false);
    }
  };

  const handleSaveDraft = async (patch: UpdateDraftInput) => {
    if (!draft) return;
    const response = await fetch(`/api/email/drafts/${draft.draftId}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(patch),
    });
    if (!response.ok) {
      const body = (await response.json()) as { error?: string };
      throw new Error(body.error ?? "Échec de la sauvegarde");
    }
    const updated = (await response.json()) as EmailDraftPreview;
    setDraft(updated);
  };

  const handleValidateAndSend = async () => {
    if (!draft) return;
    setBusy(true);
    setError(null);
    try {
      await validateEmailDraft(draft.draftId);
      const refreshed = await fetch(`/api/email/drafts/${draft.draftId}`).then(
        (r) => r.json() as Promise<EmailDraftPreview>
      );
      setDraft(refreshed);
      const proposal = await proposeEmailSend(refreshed.draftId);
      setSendProposal(proposal);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Échec de validation");
    } finally {
      setBusy(false);
    }
  };

  return (
    <aside className="flex h-full flex-col border-l border-border-subtle bg-surface">
      <div className="border-b border-border-subtle px-4 py-3">
        <div className="text-[13px] font-medium text-foreground">
          Assistant Mail
        </div>
      </div>

      <div className="flex-1 space-y-4 overflow-y-auto p-4">
        {error && (
          <p className="text-sm text-red-500" role="alert">
            {error}
          </p>
        )}

        <div className="flex flex-wrap gap-2">
          <Button
            variant="secondary"
            size="sm"
            disabled={loadingSummary}
            onClick={() => void handleSummarize()}
          >
            <Lightbulb className="h-3.5 w-3.5" />
            Résumer
          </Button>
          <Button
            variant="secondary"
            size="sm"
            disabled={busy}
            onClick={() => void handleSuggestReply()}
          >
            <Reply className="h-3.5 w-3.5" />
            Rédiger réponse
          </Button>
        </div>

        {summary && (
          <div className="rounded-[var(--radius-lg)] border border-border-subtle bg-background p-3 text-sm whitespace-pre-wrap">
            {summary}
          </div>
        )}

        {draft && (
          <div className="space-y-3">
            <DraftEditor
              draft={draft}
              disabled={busy}
              onSave={handleSaveDraft}
              onCancel={() => setDraft(null)}
            />
            <Button
              variant="primary"
              size="sm"
              disabled={busy}
              onClick={() => void handleValidateAndSend()}
            >
              Valider et préparer l&apos;envoi
            </Button>
          </div>
        )}

        {sendProposal && draft && (
          <SendConfirmation
            draft={draft}
            proposal={sendProposal}
            conversationId={draft.conversationId}
            disabled={busy}
            onConfirm={async (actionId, token) => {
              await confirmEmailSend(actionId, {
                confirmationToken: token,
                conversationId: draft.conversationId,
              });
              setSendProposal(null);
              setDraft(null);
            }}
            onCancel={async (actionId) => {
              await cancelEmailSend(actionId);
              setSendProposal(null);
            }}
            onDismiss={() => setSendProposal(null)}
          />
        )}

        {trashProposal && (
          <TrashConfirmation
            proposal={trashProposal}
            disabled={busy}
            onConfirm={async (actionId, token) => {
              try {
                const { confirmMailTrash } = await import("@/lib/mail/mail-client");
                await confirmMailTrash(actionId, token);
                onTrashConfirmed(trashProposal.messageId);
                setTrashProposal(null);
              } catch (err) {
                onTrashFailed(trashProposal.messageId);
                throw err;
              }
            }}
            onCancel={() => setTrashProposal(null)}
          />
        )}
      </div>

      <div className="border-t border-border-subtle p-4">
        <Button
          variant="secondary"
          size="sm"
          className="w-full text-red-600 hover:text-red-700"
          disabled={busy || !!trashProposal}
          onClick={async () => {
            setBusy(true);
            setError(null);
            try {
              const { proposeMailTrash } = await import("@/lib/mail/mail-client");
              const proposal = await proposeMailTrash(selectedMessageId);
              setTrashProposal(proposal);
            } catch (err) {
              setError(
                err instanceof Error ? err.message : "Impossible de préparer la corbeille"
              );
            } finally {
              setBusy(false);
            }
          }}
        >
          <Trash2 className="h-3.5 w-3.5" />
          Corbeille (ce message)
        </Button>
      </div>
    </aside>
  );
}
