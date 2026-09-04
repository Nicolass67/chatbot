#!/usr/bin/env node
/**
 * Redémarrage local manuel (sans Worker) — arrêt propre puis relance.
 */
import { loadBootConfig } from "./lib/config.mjs";
import { restartChatbotStack } from "./orchestrator.mjs";

async function main() {
  const config = loadBootConfig();
  const stack = await restartChatbotStack(config);
  if (!stack.ok) {
    console.error(`[boot] Échec étape ${stack.step}: ${stack.error ?? "unknown"}`);
    process.exit(1);
  }
  console.log("[boot] Redémarrage local terminé.");
}

main().catch((error) => {
  console.error("[boot] Erreur fatale:", error);
  process.exit(1);
});
