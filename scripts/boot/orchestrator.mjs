import { bootstrapSearxng } from "../lib/searxng-bootstrap.mjs";

import { ensureDockerReady } from "./lib/docker.mjs";

import {

  ensureLmStudioServer,

  ensureModelLoaded,

} from "./lib/lm-studio.mjs";

import {

  ensureNextJsProduction,

  fetchNextHealth,

  waitForNextHealth,

} from "./lib/nextjs.mjs";

import { isNextJsProductionReady } from "./boot-logic.mjs";
import { shutdownChatbotStack } from "./lib/shutdown-stack.mjs";
import {
  acquireBootStackLock,
  releaseBootStackLock,
} from "./lib/boot-stack-lock.mjs";



/**

 * SearXNG en arrière-plan — le chat est prêt sans attendre la recherche web.

 * @returns {Promise<void>}

 */

export function bootstrapSearxngInBackground() {

  console.log("[boot] SearXNG — démarrage en arrière-plan…");

  return bootstrapSearxng({

    fatal: false,

    waitTimeoutMs: 180_000,

  })

    .then((result) => {

      if (result.ok) {

        console.log("[boot] SearXNG prêt (arrière-plan)");

        return;

      }

      console.warn(

        `[boot] SearXNG arrière-plan incomplet : ${result.message ?? "timeout"}`

      );

    })

    .catch((error) => {

      console.warn(

        `[boot] SearXNG arrière-plan : ${error instanceof Error ? error.message : error}`

      );

    });

}



/**

 * Phase 1 — Docker, LM Studio (+ modèle), Next.js en parallèle.

 * Lance SearXNG dès que Docker est prêt (sans bloquer).

 * @param {{ lmStudioModel: string }} config

 */

export async function prewarmChatbotStack(config) {

  console.log(

    "[boot] Préchauffage parallèle : Docker + LM Studio + modèle + Next.js…"

  );



  /** @type {Promise<void> | null} */

  let searxngBackground = null;



  const dockerPromise = ensureDockerReady().then((docker) => {

    if (docker.ok && !searxngBackground) {

      searxngBackground = bootstrapSearxngInBackground();

    }

    return docker;

  });



  const lmPromise = ensureLmStudioServer().then(async (server) => {

    if (!server.ok) {

      return { server, model: { ok: false, error: server.error } };

    }

    const model = await ensureModelLoaded(config.lmStudioModel, {
      forceReload: config.forceModelReload === true,
    });

    return { server, model };

  });



  const [docker, lm] = await Promise.all([dockerPromise, lmPromise]);

  return {
    docker,
    lmServer: lm.server,
    lmModel: lm.model,
    next: { ok: true, deferred: true },
    searxngBackground,
  };

}



/**

 * Redémarrage — séquentiel côté modèle/Next pour éviter les courses.

 * @param {{ lmStudioModel: string, forceModelReload?: boolean, forceRestart?: boolean }} config

 */

export async function prewarmChatbotStackRestart(config) {

  console.log("[boot] Relance séquentielle : Docker → LM Studio → modèle → Next.js…");

  /** @type {Promise<void> | null} */

  let searxngBackground = null;

  const docker = await ensureDockerReady();

  if (docker.ok) {

    searxngBackground = bootstrapSearxngInBackground();

  }

  const lmServer = await ensureLmStudioServer();

  if (!lmServer.ok) {

    return {

      docker,

      lmServer,

      lmModel: { ok: false, error: lmServer.error },

      next: { ok: false, error: "lm_server_not_ready" },

      searxngBackground,

    };

  }

  const lmModel = await ensureModelLoaded(config.lmStudioModel, {

    forceReload: true,

  });

  if (!lmModel.ok) {

    return {

      docker,

      lmServer,

      lmModel,

      next: { ok: false, error: "model_not_ready" },

      searxngBackground,

    };

  }

  const next = await ensureNextJsProduction({ forceRestart: true });

  return { docker, lmServer, lmModel, next, searxngBackground };

}



/**

 * Phase 2 — attente health Next.js (SearXNG déjà lancé en arrière-plan).

 * @param {{ lmStudioModel: string, nextHealthUrl: string }} config

 * @param {Awaited<ReturnType<typeof prewarmChatbotStack>>} prewarm

 */

export async function finishChatbotStack(config, prewarm, options = {}) {

  const healthTimeoutMs = options.healthTimeoutMs ?? 300_000;
  const healthIntervalMs = options.healthIntervalMs ?? 1500;

  if (!prewarm.docker.ok) {

    return { ok: false, step: "docker", error: prewarm.docker.error };

  }

  if (!prewarm.lmServer.ok) {

    return { ok: false, step: "lm_studio_server", error: prewarm.lmServer.error };

  }

  if (!prewarm.lmModel.ok) {

    return { ok: false, step: "lm_studio_model", error: prewarm.lmModel.error };

  }

  if (!prewarm.next.ok || prewarm.next.deferred) {
    prewarm.next = await ensureNextJsProduction({
      forceRestart: options.forceRestart === true,
    });
  }

  if (!prewarm.next.ok) {

    return {

      ok: false,

      step: "nextjs_start",

      error: prewarm.next.error,

      message: prewarm.next.message,

    };

  }



  if (!prewarm.searxngBackground) {

    prewarm.searxngBackground = bootstrapSearxngInBackground();

  }



  console.log("[boot] Attente health Next.js (chat prêt avant SearXNG)…");

  const healthWait = await waitForNextHealth(
    config.nextHealthUrl,
    healthTimeoutMs,
    healthIntervalMs
  );

  if (!healthWait.ok) {

    return { ok: false, step: "nextjs_health", error: healthWait.error };

  }



  const { status, health } = await fetchNextHealth(config.nextHealthUrl);

  if (status !== 200 || !isNextJsProductionReady(health)) {

    return {

      ok: false,

      step: "nextjs_ready",

      error: "health_not_ready",

      health,

    };

  }



  console.log("[boot] Stack Chatbot prête (SearXNG peut encore démarrer)");

  return { ok: true, health };

}



/**

 * @param {{ lmStudioModel: string, nextHealthUrl: string }} config

 */

export async function startChatbotStack(config) {
  const lock = acquireBootStackLock("start");
  if (!lock.ok) {
    return {
      ok: false,
      step: "boot_lock",
      error: lock.reason,
      message: `Boot déjà en cours (${lock.owner})`,
    };
  }

  try {
    const prewarm = await prewarmChatbotStack(config);
    return await finishChatbotStack(config, prewarm);
  } finally {
    releaseBootStackLock();
  }
}



/**

 * Arrêt propre puis relance complète (modèle déchargé puis rechargé).

 * @param {{ lmStudioModel: string, nextHealthUrl: string }} config

 */

export async function restartChatbotStack(config) {
  const lock = acquireBootStackLock("restart");
  if (!lock.ok) {
    return {
      ok: false,
      step: "boot_lock",
      error: lock.reason,
      message: `Boot déjà en cours (${lock.owner})`,
    };
  }

  try {
    console.log("[boot] Redémarrage complet de la stack Chatbot…");

    await shutdownChatbotStack(config);

    const prewarm = await prewarmChatbotStackRestart({
      ...config,
      forceModelReload: true,
      forceRestart: true,
    });

    return finishChatbotStack(config, prewarm, {
      healthTimeoutMs: 180_000,
      healthIntervalMs: 800,
      forceRestart: true,
    });
  } finally {
    releaseBootStackLock();
  }
}

