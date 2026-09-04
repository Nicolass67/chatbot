"use client";

import { useEffect, useRef, useState } from "react";
import { Power } from "lucide-react";
import { Button } from "@/components/ui/Button";
import {
  formatShutdownPcResult,
  isShutdownPcSuccess,
  postShutdownPc,
} from "@/lib/wake/shutdown-pc-client";

const CONFIRM_TIMEOUT_MS = 8000;

export function ShutdownPcPanel() {
  const [confirming, setConfirming] = useState(false);
  const [loading, setLoading] = useState(false);
  const [output, setOutput] = useState<string | null>(null);
  const [successMessage, setSuccessMessage] = useState<string | null>(null);
  const [networkError, setNetworkError] = useState<string | null>(null);
  const confirmTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (confirmTimerRef.current) clearTimeout(confirmTimerRef.current);
    };
  }, []);

  const resetConfirm = () => {
    setConfirming(false);
    if (confirmTimerRef.current) {
      clearTimeout(confirmTimerRef.current);
      confirmTimerRef.current = null;
    }
  };

  const armConfirm = () => {
    resetConfirm();
    setConfirming(true);
    setOutput(null);
    setSuccessMessage(null);
    setNetworkError(null);
    confirmTimerRef.current = setTimeout(() => {
      setConfirming(false);
      confirmTimerRef.current = null;
    }, CONFIRM_TIMEOUT_MS);
  };

  const handleShutdown = async () => {
    if (!confirming) {
      armConfirm();
      return;
    }

    resetConfirm();
    setLoading(true);
    setOutput(null);
    setSuccessMessage(null);
    setNetworkError(null);

    try {
      const result = await postShutdownPc();
      setOutput(formatShutdownPcResult(result));

      if (isShutdownPcSuccess(result)) {
        const body = result.body as { message?: string };
        setSuccessMessage(
          body.message ??
            "Demande envoyée. Le PC s'éteindra sous environ une minute."
        );
      } else {
        const body = result.body as { message?: string; error?: string };
        setNetworkError(
          body.message ??
            body.error ??
            "La demande d'arrêt n'a pas abouti."
        );
      }
    } catch (error) {
      setNetworkError(
        error instanceof Error ? error.message : "Erreur réseau"
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="space-y-3">
      <p className="text-xs text-muted">
        Éteint le PC serveur à distance. Les services Chatbot s&apos;arrêtent
        proprement, puis Windows s&apos;éteint après ~60&nbsp;s. Annulation
        locale possible avec{" "}
        <code className="text-foreground">shutdown /a</code> sur le PC.
      </p>

      {confirming && (
        <div
          className="rounded-[var(--radius-md)] border border-error/40 bg-error/10 px-3 py-2 text-sm text-error"
          role="alert"
        >
          Confirmez l&apos;arrêt du PC. Cette action est irréversible à
          distance.
        </div>
      )}

      <Button
        type="button"
        variant={confirming ? "danger" : "secondary"}
        loading={loading}
        disabled={loading}
        onClick={() => void handleShutdown()}
        className="w-full sm:w-auto"
      >
        <Power className="mr-2 size-4" aria-hidden />
        {confirming ? "Confirmer l'arrêt du PC" : "Éteindre le PC"}
      </Button>

      {confirming && !loading && (
        <Button
          type="button"
          variant="ghost"
          size="sm"
          onClick={resetConfirm}
        >
          Annuler
        </Button>
      )}

      {successMessage && (
        <p className="text-sm text-success" role="status">
          {successMessage}
        </p>
      )}

      {networkError && (
        <p className="text-sm text-error" role="alert">
          {networkError}
        </p>
      )}

      {output && (
        <pre
          className="overflow-x-auto rounded-[var(--radius-md)] border border-border-subtle bg-surface-elevated p-3 text-xs leading-relaxed text-foreground"
          aria-live="polite"
        >
          {output}
        </pre>
      )}
    </div>
  );
}
