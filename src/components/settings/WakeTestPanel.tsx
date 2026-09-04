"use client";

import { useState } from "react";
import { Button } from "@/components/ui/Button";
import {
  formatWakeTestResult,
  postWakeTest,
} from "@/lib/wake/test-wake-client";

export function WakeTestPanel() {
  const [loading, setLoading] = useState(false);
  const [output, setOutput] = useState<string | null>(null);
  const [networkError, setNetworkError] = useState<string | null>(null);

  const runTest = async () => {
    setLoading(true);
    setOutput(null);
    setNetworkError(null);

    try {
      const result = await postWakeTest();
      setOutput(formatWakeTestResult(result));
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
        Bouton temporaire de diagnostic. Envoie{" "}
        <code className="text-foreground">POST /wake</code> via le Worker
        (session Cloudflare Access du navigateur incluse). Ne s&apos;exécute
        qu&apos;au clic.
      </p>
      <Button
        type="button"
        variant="danger"
        loading={loading}
        disabled={loading}
        onClick={runTest}
        className="w-full sm:w-auto"
      >
        TEST — Réveiller le PC
      </Button>
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
