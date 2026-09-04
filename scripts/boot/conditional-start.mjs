#!/usr/bin/env node
/**
 * Démarrage conditionnel Chatbot après WoL Worker.
 * Ne démarre RIEN si aucune demande Worker valide n'est en attente.
 *
 * Test sans redémarrage PC :
 *   1. Créer une demande via POST /wake (Access)
 *   2. node scripts/boot/conditional-start.mjs --dry-run
 *   3. node scripts/boot/conditional-start.mjs
 */
import { loadBootConfig } from "./lib/config.mjs";
import {
  consumeBootRequest,
  peekBootRequest,
  waitForWorkerBootPeek,
} from "./lib/worker-client.mjs";
import {
  waitForCloudflaredService,
  waitForInternet,
} from "./lib/network.mjs";
import { shouldStartChatbotServices } from "./boot-logic.mjs";
import {
  finishChatbotStack,
  prewarmChatbotStack,
  restartChatbotStack,
} from "./orchestrator.mjs";

const dryRun = process.argv.includes("--dry-run");

/** @type {Promise<Awaited<ReturnType<typeof prewarmChatbotStack>>> | null} */
let prewarmPromise = null;

/** @param {import("./lib/config.mjs").BootConfig} config */
/** @param {"start"|"restart"} [action] */
function kickPrewarm(config, action = "start") {
  if (dryRun || prewarmPromise || action === "restart") return;
  prewarmPromise = prewarmChatbotStack(config);
}

/** @param {import("./lib/config.mjs").BootConfig} config */
function accessAuthFromConfig(config) {
  return {
    cfAccessClientId: config.cfAccessClientId,
    cfAccessClientSecret: config.cfAccessClientSecret,
  };
}

async function main() {
  console.log("[boot] Démarrage conditionnel Chatbot…");

  let config;
  try {
    config = loadBootConfig();
  } catch (error) {
    console.error(`[boot] ${error instanceof Error ? error.message : error}`);
    process.exit(1);
  }

  console.log("[boot] Attente réseau…");
  const internet = await waitForInternet(120_000);
  if (!internet.ok) {
    console.log("[boot] Pas de réseau — arrêt (démarrage manuel supposé).");
    process.exit(0);
  }

  console.log("[boot] Worker + cloudflared en parallèle…");
  const accessAuth = accessAuthFromConfig(config);

  const workerPeekPromise = waitForWorkerBootPeek(async () => {
    try {
      const peekRes = await peekBootRequest(
        config.workerBaseUrl,
        config.bootMachineToken,
        fetch,
        accessAuth
      );
      if (peekRes.error === "access_blocked") {
        return {
          reachable: false,
          fatal: true,
          error: "access_blocked",
        };
      }
      if (!peekRes.ok) {
        return { reachable: false, error: peekRes.error };
      }
      if (peekRes.body?.pending) {
        kickPrewarm(config, peekRes.body.action ?? "start");
      }
      return { reachable: true, peek: peekRes.body ?? null };
    } catch (error) {
      return {
        reachable: false,
        error: error instanceof Error ? error.message : "fetch_failed",
      };
    }
  }, {
    timeoutMs: dryRun ? 30_000 : 120_000,
    baseDelayMs: 1500,
    maxDelayMs: 10_000,
  });

  const [tunnel, workerResult] = await Promise.all([
    waitForCloudflaredService(dryRun ? 10_000 : 45_000),
    workerPeekPromise,
  ]);

  if (!tunnel.ok) {
    console.warn("[boot] cloudflared non détecté — poursuite quand même.");
  }

  if (workerResult.error === "access_blocked") {
    console.error(
      "[boot] Cloudflare Access bloque /boot-request (302 login).\n" +
        "       Ajoutez une policy Bypass pour le chemin /boot-request dans Zero Trust,\n" +
        "       ou configurez CF_ACCESS_CLIENT_ID + CF_ACCESS_CLIENT_SECRET (Service Token) dans deploy/boot/machine.env"
    );
    process.exit(1);
  }

  if (!workerResult.reachable || !workerResult.peek) {
    console.log(
      `[boot] Worker inaccessible ou aucune réponse — arrêt (${workerResult.error ?? "no_peek"}).`
    );
    process.exit(0);
  }

  if (!workerResult.peek.pending) {
    console.log(
      `[boot] Aucune demande Worker valide (status=${workerResult.peek.status ?? "none"}) — arrêt.`
    );
    console.log("[boot] Démarrage manuel détecté : services Chatbot non lancés.");
    process.exit(0);
  }

  if (dryRun) {
    console.log(
      `[boot] DRY-RUN : demande pending ${workerResult.peek.requestId} (${workerResult.peek.action ?? "start"}) — services NON démarrés.`
    );
    process.exit(0);
  }

  const action = workerResult.peek.action ?? "start";

  if (action === "restart") {
    console.log(
      `[boot] Redémarrage demandé (${workerResult.peek.requestId}) — arrêt puis relance…`
    );

    const consumeRes = await consumeBootRequest(
      config.workerBaseUrl,
      config.bootMachineToken,
      workerResult.peek.requestId,
      fetch,
      accessAuth
    );

    const decision = shouldStartChatbotServices(workerResult.peek, {
      consumed: consumeRes.consumed === true,
    });

    if (!decision.start) {
      console.log(`[boot] Redémarrage refusé (${decision.reason}).`);
      process.exit(0);
    }

    const stack = await restartChatbotStack(config);
    if (!stack.ok) {
      console.error(`[boot] Échec étape ${stack.step}: ${stack.error ?? "unknown"}`);
      process.exit(1);
    }

    console.log("[boot] Redémarrage terminé avec succès.");
    process.exit(0);
  }

  if (action === "shutdown") {
    console.log(
      `[boot] Extinction demandée (${workerResult.peek.requestId})…`
    );

    const consumeRes = await consumeBootRequest(
      config.workerBaseUrl,
      config.bootMachineToken,
      workerResult.peek.requestId,
      fetch,
      accessAuth
    );

    const decision = shouldStartChatbotServices(workerResult.peek, {
      consumed: consumeRes.consumed === true,
    });

    if (!decision.start) {
      console.log(`[boot] Extinction refusée (${decision.reason}).`);
      process.exit(0);
    }

    const { shutdownWindowsPc } = await import("./lib/shutdown-pc.mjs");
    const shutdown = await shutdownWindowsPc(config);
    if (!shutdown.ok) {
      console.error(`[boot] Échec extinction: ${shutdown.error ?? "unknown"}`);
      process.exit(1);
    }

    console.log(
      `[boot] Extinction PC planifiée dans ${shutdown.delaySeconds}s.`
    );
    process.exit(0);
  }

  kickPrewarm(config, action);

  console.log(
    `[boot] Demande pending — préchauffage + consommation en parallèle…`
  );

  const [consumeRes, prewarm] = await Promise.all([
    consumeBootRequest(
      config.workerBaseUrl,
      config.bootMachineToken,
      workerResult.peek.requestId,
      fetch,
      accessAuth
    ),
    prewarmPromise ?? prewarmChatbotStack(config),
  ]);

  const decision = shouldStartChatbotServices(workerResult.peek, {
    consumed: consumeRes.consumed === true,
  });

  if (!decision.start) {
    console.log(`[boot] Démarrage refusé (${decision.reason}).`);
    process.exit(0);
  }

  console.log(
    `[boot] Demande Worker consommée (${workerResult.peek.requestId}) — finalisation stack…`
  );

  const stack = await finishChatbotStack(config, prewarm);
  if (!stack.ok) {
    console.error(`[boot] Échec étape ${stack.step}: ${stack.error ?? "unknown"}`);
    process.exit(1);
  }

  console.log("[boot] Terminé avec succès.");
}

main().catch((error) => {
  console.error("[boot] Erreur fatale:", error);
  process.exit(1);
});
