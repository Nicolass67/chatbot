import { spawnSync } from "node:child_process";
import { shutdownChatbotStack } from "./shutdown-stack.mjs";

const DEFAULT_DELAY_SECONDS = 60;

/**
 * Arrêt propre de la stack puis extinction Windows planifiée.
 * @param {import("./config.mjs").BootConfig} config
 * @param {{ delaySeconds?: number }} [options]
 */
export async function shutdownWindowsPc(config, options = {}) {
  const delaySeconds = options.delaySeconds ?? DEFAULT_DELAY_SECONDS;

  if (process.platform !== "win32") {
    return {
      ok: false,
      error: "unsupported_platform",
      message: "Extinction PC supportée uniquement sous Windows",
    };
  }

  console.log(
    `[boot] Arrêt propre stack puis extinction PC dans ${delaySeconds}s…`
  );

  try {
    await shutdownChatbotStack(config);
  } catch (error) {
    console.warn(
      "[boot] Stack — arrêt partiel avant extinction:",
      error instanceof Error ? error.message : error
    );
  }

  const result = spawnSync(
    "shutdown",
    [
      "/s",
      "/full",
      "/t",
      String(delaySeconds),
      "/c",
      "Arrêt demandé depuis Chatbot (annulable : shutdown /a)",
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
      detail: (result.stderr || result.stdout || "").trim(),
    };
  }

  console.log(
    `[boot] Extinction planifiée dans ${delaySeconds}s (annulation : shutdown /a)`
  );
  return { ok: true, delaySeconds };
}
