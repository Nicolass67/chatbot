import { spawnSync } from "node:child_process";

export const HOST_SHUTDOWN_DELAY_SECONDS = 60;

export type HostShutdownResult =
  | {
      ok: true;
      delaySeconds: number;
      message: string;
      cancelHint: string;
    }
  | {
      ok: false;
      error: string;
      message: string;
      detail?: string;
    };

/**
 * Planifie l'extinction Windows du PC hôte (stack arrêtée par Windows ensuite).
 * Appelé depuis l'API authentifiée — le Next tourne déjà sur le PC.
 */
export function scheduleHostPcShutdown(
  delaySeconds = HOST_SHUTDOWN_DELAY_SECONDS
): HostShutdownResult {
  if (process.platform !== "win32") {
    return {
      ok: false,
      error: "unsupported_platform",
      message: "L'extinction du PC n'est disponible que sur l'hôte Windows.",
    };
  }

  const safeDelay = Math.max(15, Math.min(delaySeconds, 600));
  const result = spawnSync(
    "shutdown",
    [
      "/s",
      "/full",
      "/t",
      String(safeDelay),
      "/c",
      "Arrêt demandé depuis Chatbot (annulation locale : shutdown /a)",
    ],
    {
      encoding: "utf8",
      windowsHide: true,
    }
  );

  if (result.status !== 0) {
    return {
      ok: false,
      error: "shutdown_failed",
      message: "Impossible de planifier l'extinction du PC.",
      detail: (result.stderr || result.stdout || "").trim() || undefined,
    };
  }

  return {
    ok: true,
    delaySeconds: safeDelay,
    message: `Extinction planifiée dans environ ${safeDelay} secondes.`,
    cancelHint: "Sur le PC : shutdown /a",
  };
}
