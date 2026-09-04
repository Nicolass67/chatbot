#!/usr/bin/env node
/**
 * Exécute une demande Worker déjà peekée : consume + start/restart direct.
 * Évite le double polling de conditional-start (gain ~0-120s).
 */
import { shouldStartChatbotServices } from "./boot-logic.mjs";
import { loadBootConfig } from "./lib/config.mjs";
import {
  consumeBootRequest,
  peekBootRequest,
} from "./lib/worker-client.mjs";
import {
  restartChatbotStack,
  startChatbotStack,
} from "./orchestrator.mjs";
import { shutdownWindowsPc } from "./lib/shutdown-pc.mjs";

/** @param {import("./lib/config.mjs").BootConfig} config */
function accessAuthFromConfig(config) {
  return {
    cfAccessClientId: config.cfAccessClientId,
    cfAccessClientSecret: config.cfAccessClientSecret,
  };
}

async function main() {
  const config = loadBootConfig();
  const accessAuth = accessAuthFromConfig(config);

  const peekRes = await peekBootRequest(
    config.workerBaseUrl,
    config.bootMachineToken,
    fetch,
    accessAuth
  );

  if (peekRes.error === "access_blocked") {
    console.error("[boot] Cloudflare Access bloque /boot-request.");
    process.exit(1);
  }

  if (!peekRes.ok || !peekRes.body?.pending) {
    console.log("[boot] Aucune demande Worker pending.");
    process.exit(0);
  }

  const action = peekRes.body.action ?? "start";
  const requestId = peekRes.body.requestId;

  const consumeRes = await consumeBootRequest(
    config.workerBaseUrl,
    config.bootMachineToken,
    requestId,
    fetch,
    accessAuth
  );

  const decision = shouldStartChatbotServices(peekRes.body, {
    consumed: consumeRes.consumed === true,
  });

  if (!decision.start) {
    console.log(`[boot] Exécution refusée (${decision.reason}).`);
    process.exit(0);
  }

  console.log(`[boot] Exécution ${action} (${requestId})…`);

  if (action === "shutdown") {
    const shutdown = await shutdownWindowsPc(config);
    if (!shutdown.ok) {
      console.error(
        `[boot] Échec extinction: ${shutdown.error ?? "unknown"}`
      );
      process.exit(1);
    }
    console.log(
      `[boot] Extinction PC planifiée dans ${shutdown.delaySeconds}s.`
    );
    process.exit(0);
  }

  const stack =
    action === "restart"
      ? await restartChatbotStack(config)
      : await startChatbotStack(config);

  if (!stack.ok) {
    console.error(`[boot] Échec étape ${stack.step}: ${stack.error ?? "unknown"}`);
    process.exit(1);
  }

  console.log(`[boot] ${action === "restart" ? "Redémarrage" : "Démarrage"} terminé.`);
}

main().catch((error) => {
  console.error("[boot] Erreur fatale:", error);
  process.exit(1);
});
