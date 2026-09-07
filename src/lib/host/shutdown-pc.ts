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
  // Pas de /full : absent de shutdown.exe sur Win10/11 FR → exit 1 + aide syntaxe.
  const result = spawnSync(
    "shutdown.exe",
    [
      "/s",
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
    const detail = (result.stderr || result.stdout || "").trim() || undefined;
    return {
      ok: false,
      error: "shutdown_failed",
      message: detail
        ? `Impossible de planifier l'extinction du PC (${detail.slice(0, 180)})`
        : "Impossible de planifier l'extinction du PC.",
      detail,
    };
  }

  return {
    ok: true,
    delaySeconds: safeDelay,
    message: `Extinction planifiée dans environ ${safeDelay} secondes.`,
    cancelHint: "Sur le PC : shutdown /a",
  };
}
