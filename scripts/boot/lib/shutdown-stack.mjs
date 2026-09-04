import { sleep } from "./network.mjs";
import { stopSearxngStack } from "../../lib/searxng-bootstrap.mjs";
import {
  isLmStudioApiReady,
  isLmStudioPortListening,
  listLoadedLlmInstances,
  unloadAllLoadedModels,
} from "./lm-studio.mjs";
import { isNextJsListening, stopNextJsProduction } from "./nextjs.mjs";
import { ensureDockerReady } from "./docker.mjs";

/** @param {import("./config.mjs").BootConfig} config */
export async function auditStackStatus(config) {
  const [nextJs, lmPort, docker] = await Promise.all([
    isNextJsListening(),
    isLmStudioPortListening(),
    ensureDockerReady(),
  ]);

  const lmStudioApi = lmPort ? await isLmStudioApiReady() : false;
  let loadedModels = [];
  if (lmStudioApi) {
    try {
      loadedModels = await listLoadedLlmInstances();
    } catch {
      loadedModels = [];
    }
  }

  return {
    nextJs,
    lmStudioApi,
    docker: docker.ok,
    loadedModels: loadedModels.map((m) => m.modelKey),
    nextHealthUrl: config.nextHealthUrl,
  };
}

/** @param {import("./config.mjs").BootConfig} config */
export async function shutdownChatbotStack(config) {
  const status = await auditStackStatus(config);
  console.log(
    `[boot] Arrêt stack — Next.js=${status.nextJs ? "up" : "down"}, LM Studio=${status.lmStudioApi ? "up" : "down"}, modèles=[${status.loadedModels.join(", ") || "aucun"}]`
  );

  const [nextStop, searxngStop] = await Promise.all([
    status.nextJs
      ? stopNextJsProduction()
      : Promise.resolve({ ok: true, method: "already_stopped" }),
    Promise.resolve(stopSearxngStack()),
  ]);

  let modelUnload = { ok: true, unloadedCount: 0 };
  if (status.lmStudioApi) {
    modelUnload = await unloadAllLoadedModels();
    await sleep(2000);
  }

  if (!nextStop.ok) {
    console.warn(`[boot] Next.js — arrêt incomplet (${nextStop.error ?? "unknown"})`);
  } else if (status.nextJs) {
    console.log("[boot] Next.js arrêté");
  }

  if (!searxngStop.ok) {
    console.warn("[boot] SearXNG — arrêt incomplet ou déjà arrêté");
  }

  if (!modelUnload.ok) {
    throw new Error(
      `Déchargement modèles échoué (${modelUnload.error ?? "unknown"})`
    );
  }
  if (modelUnload.unloadedCount > 0) {
    console.log(
      `[boot] LM Studio — ${modelUnload.unloadedCount} modèle(s) déchargé(s)`
    );
  }

  await sleep(500);
  return { ok: true, previous: status };
}
