"use client";

import { useState } from "react";
import { AlertTriangle, Trash2 } from "lucide-react";
import { Button } from "@/components/ui/Button";
import type { ProposeTrashEmailResult } from "@/lib/email/trash/types";
import { cn } from "@/lib/utils/cn";

interface TrashConfirmationProps {
  proposal: ProposeTrashEmailResult;
  disabled?: boolean;
  onConfirm: (
    actionId: string,
    confirmationToken: string
  ) => Promise<void>;
  onCancel: () => void;
  className?: string;
}

export function TrashConfirmation({
  proposal,
  disabled,
  onConfirm,
  onCancel,
  className,
}: TrashConfirmationProps) {
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleConfirm = async () => {
    setConfirming(true);
    setError(null);
    try {
      await onConfirm(proposal.actionId, proposal.confirmationToken);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Échec de la corbeille");
    } finally {
      setConfirming(false);
    }
  };

  return (
    <div
      className={cn(
        "rounded-[var(--radius-xl)] border border-amber-500/30 bg-amber-500/5 p-4",
        className
      )}
    >
      <div className="mb-3 flex items-start gap-2">
        <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-amber-500" />
        <div>
          <p className="text-sm font-medium text-foreground">
            Mettre ce message à la corbeille
          </p>
          <p className="mt-1 text-xs text-muted-foreground">
            Seul le message sélectionné sera déplacé — pas toute la conversation.
          </p>
        </div>
      </div>
      <dl className="mb-4 space-y-1 text-sm">
        <div>
          <dt className="text-muted-foreground">De</dt>
          <dd>{proposal.messageSnapshot.from}</dd>
        </div>
        <div>
          <dt className="text-muted-foreground">Objet</dt>
          <dd>{proposal.messageSnapshot.subject}</dd>
        </div>
      </dl>
      {error && (
        <p className="mb-3 text-sm text-red-500" role="alert">
          {error}
        </p>
      )}
      <div className="flex flex-wrap gap-2">
        <Button
          variant="danger"
          size="sm"
          disabled={disabled || confirming}
          onClick={() => void handleConfirm()}
        >
          <Trash2 className="h-3.5 w-3.5" />
          Confirmer la corbeille
        </Button>
        <Button
          variant="secondary"
          size="sm"
          disabled={confirming}
          onClick={onCancel}
        >
          Annuler
        </Button>
      </div>
    </div>
  );
}
