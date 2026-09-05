#!/usr/bin/env node
/**
 * Chatbot Supervisor — independent of Next.js (no src/ imports).
 *
 * Watches: docker, searxng, nextjs, lm_studio, cloudflared
 * Minimal repair blast radius + crash-loop circuit breaker
 * Localhost API 127.0.0.1:3927 + data/supervisor/*.json
 *
 * node scripts/supervisor/index.mjs
 */

import { spawn, execFile } from "node:child_process";
import { createServer } from "node:http";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "../..");
const DATA_DIR = path.join(ROOT, "data", "supervisor");
const STATUS_FILE = path.join(DATA_DIR, "status.json");
const COMMAND_FILE = path.join(DATA_DIR, "command.json");
const INCIDENTS_FILE = path.join(DATA_DIR, "incidents.json");
const LOCK_FILE = path.join(DATA_DIR, "repair.lock");
const PORT = Number(process.env.CHATBOT_SUPERVISOR_PORT || 3927);
const TICK_MS = Number(process.env.CHATBOT_SUPERVISOR_INTERVAL_MS || 12_000);
const CRASH_WINDOW_MS = 15 * 60_000;
const AUTO_REPAIR_STREAK = 2;
const NPM_CMD = process.platform === "win32" ? "npm.cmd" : "npm";

const SERVICES = [
  {
    id: "docker",
    displayName: "Docker",
    humanName: "Moteur conteneurs",
    category: "platform",
    criticality: "optional",
    dependencies: [],
  },
  {
    id: "searxng",
    displayName: "SearXNG",
    humanName: "Recherche Web",
    category: "search",
    criticality: "optional",
    dependencies: ["docker"],
  },
  {
    id: "nextjs",
    displayName: "Chatbot",
    humanName: "Chatbot",
    category: "core",
    criticality: "required",
    dependencies: [],
  },
  {
    id: "lm_studio",
    displayName: "LM Studio",
    humanName: "Assistant IA",
    category: "ai",
    criticality: "optional",
    dependencies: [],
  },
  {
    id: "cloudflared",
    displayName: "Tunnel",
    humanName: "Connexion distante",
    category: "ingress",
    criticality: "optional",
    dependencies: ["nextjs"],
  },
];

/** @type {Map<string, number[]>} */
const restartHistory = new Map();
/** @type {Map<string, number>} */
const failStreak = new Map();
let repairing = false;
let activeRepairId = null;

function ensureDir() {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

function writeJson(file, data) {
  ensureDir();
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2), "utf8");
  fs.renameSync(tmp, file);
}

function log(level, msg, extra) {
  console.log(
    JSON.stringify({
      ts: new Date().toISOString(),
      level,
      msg,
      ...(extra || {}),
    })
  );
}

function run(cmd, args, timeoutMs = 20_000) {
  return new Promise((resolve) => {
    execFile(
      cmd,
      args,
      { timeout: timeoutMs, windowsHide: true, cwd: ROOT },
      (err, stdout, stderr) => {
        resolve({
          ok: !err,
          stdout: String(stdout || ""),
          stderr: String(stderr || ""),
        });
      }
    );
  });
}

async function httpProbe(url, timeoutMs = 5000) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: ctrl.signal, redirect: "follow" });
    let body = null;
    const text = await res.text();
    try {
      body = text ? JSON.parse(text) : null;
    } catch {
      body = null;
    }
    return { ok: res.ok, status: res.status, body };
  } catch (e) {
    return {
      ok: false,
      status: 0,
      error: e instanceof Error ? e.message : String(e),
      body: null,
    };
  } finally {
    clearTimeout(timer);
  }
}

async function probeDocker() {
  const r = await run("docker", ["info"], 12_000);
  return {
    process: r.ok ? "running" : "stopped",
    health: r.ok ? "healthy" : "unhealthy",
    readiness: r.ok ? "ready" : "not_ready",
    summary: r.ok ? "Docker disponible" : "Docker indisponible",
  };
}

async function probeSearxng() {
  const r = await httpProbe("http://127.0.0.1:8080/", 8000);
  const ok = r.ok || [200, 301, 302].includes(r.status);
  return {
    process: ok ? "running" : "stopped",
    health: ok ? "healthy" : "unhealthy",
    readiness: ok ? "ready" : "not_ready",
    summary: ok
      ? "Recherche Web opérationnelle"
      : "Recherche Web indisponible",
  };
}

async function probeNextjs() {
  const r = await httpProbe("http://127.0.0.1:3000/api/health", 5000);
  if (r.status === 0) {
    return {
      process: "stopped",
      health: "unhealthy",
      readiness: "not_ready",
      summary: "Chatbot inaccessible",
    };
  }
  const label = r.body?.status;
  const ok =
    r.status === 200 ||
    label === "ok" ||
    label === "degraded" ||
    r.body?.ready === true;
  return {
    process: "running",
    health: ok ? "healthy" : "unhealthy",
    readiness: ok ? "ready" : "not_ready",
    summary: ok
      ? "Chatbot opérationnel"
      : "Chatbot ne répond pas correctement",
  };
}

async function probeLmStudio() {
  const r = await httpProbe("http://127.0.0.1:1234/v1/models", 8000);
  if (r.status === 0) {
    return {
      process: "stopped",
      health: "unhealthy",
      readiness: "not_ready",
      summary: "Assistant IA indisponible",
    };
  }
  const models = Array.isArray(r.body?.data) ? r.body.data : [];
  const hasModel = models.length > 0;
  return {
    process: "running",
    health: r.ok ? "healthy" : "unhealthy",
    readiness: hasModel ? "ready" : "not_ready",
    summary: !r.ok
      ? "Assistant IA indisponible"
      : hasModel
        ? "Assistant IA prêt"
        : "Assistant IA démarré — modèle non prêt",
  };
}

async function probeCloudflared() {
  if (process.platform !== "win32") {
    return {
      process: "unknown",
      health: "unknown",
      readiness: "unknown",
      summary: "Tunnel : état inconnu hors Windows",
    };
  }
  for (const name of ["Cloudflared", "cloudflared"]) {
    const r = await run("sc.exe", ["query", name], 8000);
    if (/RUNNING/i.test(`${r.stdout}\n${r.stderr}`)) {
      return {
        process: "running",
        health: "healthy",
        readiness: "ready",
        summary: "Connexion distante opérationnelle",
      };
    }
  }
  return {
    process: "stopped",
    health: "unhealthy",
    readiness: "not_ready",
    summary: "Tunnel Cloudflare arrêté",
  };
}

const PROBES = {
  docker: probeDocker,
  searxng: probeSearxng,
  nextjs: probeNextjs,
  lm_studio: probeLmStudio,
  cloudflared: probeCloudflared,
};

/** Max restarts in 15 min: nextjs=5, others=4 → crashLoop true, skip repair. */
function isCrashLoop(serviceId) {
  const now = Date.now();
  const max = serviceId === "nextjs" ? 5 : 4;
  const list = (restartHistory.get(serviceId) || []).filter(
    (t) => now - t < CRASH_WINDOW_MS
  );
  restartHistory.set(serviceId, list);
  return list.length >= max;
}

function noteRestart(serviceId) {
  const list = restartHistory.get(serviceId) || [];
  list.push(Date.now());
  restartHistory.set(serviceId, list);
}

function isDown(s) {
  return (
    s.crashLoop || s.process === "stopped" || s.health === "unhealthy"
  );
}

/** True if serviceId transitively depends on depId. */
function dependsOn(serviceId, depId) {
  const def = SERVICES.find((s) => s.id === serviceId);
  if (!def) return false;
  const queue = [...def.dependencies];
  const seen = new Set();
  while (queue.length) {
    const id = queue.shift();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    if (id === depId) return true;
    const d = SERVICES.find((s) => s.id === id);
    if (d) queue.push(...d.dependencies);
  }
  return false;
}

async function collectStatus() {
  const services = [];
  for (const def of SERVICES) {
    const probe = await PROBES[def.id]();
    const bad = probe.health === "unhealthy" || probe.process === "stopped";
    failStreak.set(
      def.id,
      bad ? (failStreak.get(def.id) || 0) + 1 : 0
    );
    const crashLoop = isCrashLoop(def.id);
    services.push({
      id: def.id,
      displayName: def.displayName,
      humanName: def.humanName,
      category: def.category,
      criticality: def.criticality,
      process: probe.process,
      health: probe.health,
      readiness: probe.readiness,
      summary: crashLoop
        ? `${def.humanName} instable (trop de redémarrages)`
        : probe.summary,
      lastCheckAt: new Date().toISOString(),
      lastRecoveryAt: null,
      restartCount: (restartHistory.get(def.id) || []).length,
      incidentId: null,
      crashLoop,
    });
  }

  const requiredDown = services.some(
    (s) =>
      s.criticality === "required" &&
      (s.health === "unhealthy" || s.process === "stopped" || s.crashLoop)
  );
  const optionalDown = services.some(
    (s) =>
      s.criticality === "optional" &&
      (s.health === "unhealthy" ||
        s.process === "stopped" ||
        (s.id === "lm_studio" && s.readiness === "not_ready"))
  );

  let overallState = "healthy";
  let message = "Tout est opérationnel";
  if (repairing) {
    overallState = "recovering";
    message = "Réparation en cours…";
  } else if (requiredDown) {
    overallState = "error";
    const d = services.find(
      (s) =>
        s.criticality === "required" &&
        (s.health === "unhealthy" || s.process === "stopped")
    );
    message = d
      ? `${d.humanName} nécessite une attention`
      : "Problème critique";
  } else if (optionalDown) {
    overallState = "degraded";
    const d = services.find(
      (s) =>
        s.criticality === "optional" &&
        (s.health === "unhealthy" ||
          s.process === "stopped" ||
          s.readiness === "not_ready")
    );
    message = d ? `${d.humanName} indisponible` : "Fonctionnement dégradé";
  }

  return {
    overallState,
    powerState: "online",
    generatedAt: new Date().toISOString(),
    supervisorAlive: true,
    message,
    services,
    activeRepairId,
  };
}

/**
 * Minimal plan: only down services (+ their down deps).
 * Crash-loop targets are listed but get no repair actions.
 */
function buildPlan(services, onlyServiceId) {
  let targets = services.filter(isDown);
  if (onlyServiceId) {
    targets = targets.filter((s) => s.id === onlyServiceId);
    for (const s of services) {
      if (
        s.id !== onlyServiceId &&
        isDown(s) &&
        dependsOn(onlyServiceId, s.id)
      ) {
        targets.push(s);
      }
    }
  }

  const expanded = new Map();
  for (const t of targets) {
    expanded.set(t.id, t);
    for (const def of SERVICES) {
      if (!dependsOn(t.id, def.id)) continue;
      const dep = services.find((x) => x.id === def.id);
      if (dep && isDown(dep)) expanded.set(def.id, dep);
    }
  }

  const ordered = [...expanded.values()].sort((a, b) => {
    if (dependsOn(a.id, b.id)) return 1;
    if (dependsOn(b.id, a.id)) return -1;
    return 0;
  });

  const actions = [];
  for (const s of ordered) {
    if (s.crashLoop) continue;
    if (s.id === "docker") {
      actions.push({ type: "ensure_docker", serviceId: s.id });
    } else if (s.id === "searxng") {
      actions.push({ type: "start_docker_container", serviceId: s.id });
    } else if (
      s.id === "lm_studio" &&
      s.process === "running" &&
      s.readiness === "not_ready"
    ) {
      actions.push({ type: "reload_model", serviceId: s.id });
    } else if (s.id === "lm_studio") {
      actions.push({ type: "start_service", serviceId: s.id });
    } else if (s.id === "cloudflared") {
      actions.push({ type: "refresh_tunnel", serviceId: s.id });
    } else {
      actions.push({ type: "restart_service", serviceId: s.id });
    }
    actions.push({ type: "wait_for_health", serviceId: s.id });
  }

  return {
    planId: `plan-${Date.now().toString(36)}`,
    targetServiceIds: ordered.map((s) => s.id),
    untouchedServiceIds: services
      .map((s) => s.id)
      .filter((id) => !expanded.has(id)),
    actions,
  };
}

async function runAction(action) {
  const { type, serviceId } = action;

  if (type === "wait_for_health") {
    await new Promise((r) => setTimeout(r, 2500));
    const probe = await PROBES[serviceId]();
    return {
      type,
      serviceId,
      ok:
        probe.health === "healthy" ||
        (serviceId === "lm_studio" && probe.process === "running"),
      detail: probe.summary,
    };
  }

  if (type === "ensure_docker") {
    if (process.platform === "win32") {
      spawn("cmd.exe", ["/c", "start", "", "Docker Desktop"], {
        detached: true,
        stdio: "ignore",
        windowsHide: true,
      }).unref();
    }
    await new Promise((r) => setTimeout(r, 8000));
    const probe = await probeDocker();
    return {
      type,
      serviceId,
      ok: probe.health === "healthy",
      detail: probe.summary,
    };
  }

  if (type === "start_docker_container" && serviceId === "searxng") {
    noteRestart(serviceId);
    const r = await run(NPM_CMD, ["run", "searxng:start"], 120_000);
    return {
      type,
      serviceId,
      ok: r.ok,
      detail: r.ok
        ? "Conteneur SearXNG démarré"
        : r.stderr || r.stdout || "échec",
    };
  }

  if (type === "restart_service" && serviceId === "nextjs") {
    noteRestart(serviceId);
    let r = await run(NPM_CMD, ["run", "boot:restart"], 180_000);
    if (!r.ok) {
      r = await run(NPM_CMD, ["run", "start:prod"], 120_000);
    }
    return {
      type,
      serviceId,
      ok: true,
      detail: r.ok ? "Chatbot relancé" : "Redémarrage Chatbot demandé",
    };
  }

  if (type === "start_service" && serviceId === "lm_studio") {
    noteRestart(serviceId);
    if (process.platform === "win32") {
      spawn("cmd.exe", ["/c", "start", "", "lms", "server", "start"], {
        detached: true,
        stdio: "ignore",
        windowsHide: true,
      }).unref();
    }
    return {
      type,
      serviceId,
      ok: true,
      detail: "LM Studio — démarrage demandé",
    };
  }

  if (type === "reload_model") {
    noteRestart(serviceId);
    return {
      type,
      serviceId,
      ok: true,
      detail: "Attente readiness modèle",
    };
  }

  if (type === "refresh_tunnel") {
    noteRestart(serviceId);
    if (process.platform === "win32") {
      for (const name of ["Cloudflared", "cloudflared"]) {
        await run("sc.exe", ["stop", name], 15_000);
        await new Promise((r) => setTimeout(r, 1500));
        const r = await run("sc.exe", ["start", name], 15_000);
        if (r.ok) break;
      }
    }
    return { type, serviceId, ok: true, detail: "Tunnel relancé" };
  }

  return {
    type,
    serviceId,
    ok: false,
    detail: `Action non supportée: ${type}`,
  };
}

async function executePlan(plan) {
  if (repairing) {
    return {
      planId: plan.planId,
      status: "already_in_progress",
      message: "Une réparation est déjà en cours",
      repairedServices: [],
      untouchedServices: plan.untouchedServiceIds,
      actions: [],
      durationMs: 0,
    };
  }

  if (!plan.actions.length) {
    const crashOnly = plan.targetServiceIds.some((id) => {
      const hist = restartHistory.get(id) || [];
      const now = Date.now();
      const max = id === "nextjs" ? 5 : 4;
      return hist.filter((t) => now - t < CRASH_WINDOW_MS).length >= max;
    });
    return {
      planId: plan.planId,
      status: "skipped",
      message: crashOnly
        ? "Un service est instable (trop de redémarrages). Réessaie plus tard."
        : "Aucun problème à réparer.",
      repairedServices: [],
      untouchedServices: plan.untouchedServiceIds,
      actions: [],
      durationMs: 0,
    };
  }

  repairing = true;
  activeRepairId = plan.planId;
  const started = Date.now();
  const actionResults = [];

  try {
    ensureDir();
    fs.writeFileSync(LOCK_FILE, plan.planId, "utf8");

    for (const action of plan.actions) {
      log("info", "repair_action", action);
      actionResults.push(await runAction(action));
    }

    const failed = actionResults.filter((a) => !a.ok);
    const status =
      failed.length === 0
        ? "success"
        : failed.length === actionResults.length
          ? "failed"
          : "partial";

    const repaired = [...new Set(plan.targetServiceIds)];
    const names = repaired
      .map((id) => SERVICES.find((s) => s.id === id)?.humanName || id)
      .join(", ");

    const message =
      status === "success"
        ? `Réparation terminée. ${names} rétablie(s). Les autres services n’ont pas été touchés.`
        : status === "partial"
          ? "Réparation partielle — certains contrôles ont échoué"
          : "Réparation échouée";

    const result = {
      planId: plan.planId,
      incidentId: `inc-${Date.now().toString(36)}`,
      status,
      actions: actionResults,
      repairedServices: repaired,
      untouchedServices: plan.untouchedServiceIds,
      durationMs: Date.now() - started,
      message,
    };

    writeJson(path.join(DATA_DIR, "last-repair.json"), result);

    let incidents = [];
    try {
      if (fs.existsSync(INCIDENTS_FILE)) {
        incidents = JSON.parse(fs.readFileSync(INCIDENTS_FILE, "utf8"));
      }
    } catch {
      incidents = [];
    }
    incidents.unshift({
      id: result.incidentId,
      serviceId: repaired[0] || "system",
      detectedAt: new Date(started).toISOString(),
      resolvedAt: status === "success" ? new Date().toISOString() : null,
      category: "health_down",
      diagnosis: message,
      actions: actionResults.map(
        (a) => `${a.type}:${a.serviceId}:${a.ok ? "ok" : "fail"}`
      ),
      result:
        status === "success"
          ? "recovered"
          : status === "failed"
            ? "failed"
            : "open",
      restartCount: repaired.reduce(
        (n, id) => n + (restartHistory.get(id)?.length || 0),
        0
      ),
      durationMs: result.durationMs,
    });
    writeJson(INCIDENTS_FILE, incidents.slice(0, 100));

    return result;
  } finally {
    repairing = false;
    activeRepairId = null;
    try {
      fs.unlinkSync(LOCK_FILE);
    } catch {
      /* ignore */
    }
  }
}

async function consumeCommand() {
  if (!fs.existsSync(COMMAND_FILE)) return;
  let cmd = null;
  try {
    cmd = JSON.parse(fs.readFileSync(COMMAND_FILE, "utf8"));
    fs.unlinkSync(COMMAND_FILE);
  } catch {
    cmd = null;
  }
  if (!cmd) return;
  if (
    cmd.type !== "repair" &&
    cmd.type !== "repair_service" &&
    cmd.type !== "diagnose"
  ) {
    return;
  }

  const status = await collectStatus();
  const only =
    cmd.type === "repair_service" ? cmd.serviceId : undefined;
  const plan = buildPlan(status.services, only);
  writeJson(path.join(DATA_DIR, "last-plan.json"), plan);
  if (cmd.type !== "diagnose") {
    await executePlan(plan);
  }
}

async function tick() {
  try {
    await consumeCommand();

    const status = await collectStatus();
    for (const s of status.services) {
      const streak = failStreak.get(s.id) || 0;
      if (
        !repairing &&
        !s.crashLoop &&
        streak >= AUTO_REPAIR_STREAK &&
        isDown(s)
      ) {
        log("warn", "auto_repair", { serviceId: s.id, streak });
        await executePlan(buildPlan(status.services, s.id));
        break;
      }
    }

    writeJson(STATUS_FILE, await collectStatus());
  } catch (e) {
    log("error", "tick_failed", {
      error: e instanceof Error ? e.message : String(e),
    });
  }
}

function startApi() {
  const server = createServer(async (req, res) => {
    const url = new URL(req.url || "/", `http://127.0.0.1:${PORT}`);
    res.setHeader("Content-Type", "application/json");

    if (url.pathname === "/health") {
      res.end(JSON.stringify({ ok: true, supervisor: true }));
      return;
    }

    if (url.pathname === "/status") {
      try {
        if (fs.existsSync(STATUS_FILE)) {
          res.end(fs.readFileSync(STATUS_FILE, "utf8"));
        } else {
          res.end(
            JSON.stringify({ supervisorAlive: true, services: [] })
          );
        }
      } catch (e) {
        res.statusCode = 500;
        res.end(JSON.stringify({ error: String(e) }));
      }
      return;
    }

    if (url.pathname === "/repair" && req.method === "POST") {
      let body = "";
      for await (const chunk of req) body += chunk;
      let parsed = {};
      try {
        parsed = body ? JSON.parse(body) : {};
      } catch {
        parsed = {};
      }
      const status = await collectStatus();
      const result = await executePlan(
        buildPlan(status.services, parsed.serviceId)
      );
      res.end(JSON.stringify(result));
      return;
    }

    res.statusCode = 404;
    res.end(JSON.stringify({ error: "not_found" }));
  });

  server.listen(PORT, "127.0.0.1", () =>
    log("info", "local_api_listening", { port: PORT })
  );
}

async function main() {
  ensureDir();
  log("info", "supervisor_start", { root: ROOT, pid: process.pid });
  startApi();
  await tick();
  setInterval(tick, TICK_MS);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
