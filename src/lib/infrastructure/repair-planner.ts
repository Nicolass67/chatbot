import { randomUUID } from "node:crypto";
import { dependsOn } from "./dependency-graph";
import { getServiceDefinition, SERVICE_REGISTRY } from "./service-registry";
import type {
  DiagnosticResult,
  OverallState,
  RepairAction,
  RepairPlan,
  ServiceStatusSnapshot,
} from "./types";

function isDown(s: ServiceStatusSnapshot): boolean {
  if (s.crashLoop) return true;
  if (s.process === "stopped" || s.process === "unknown") return true;
  if (s.health === "unhealthy") return true;
  // LM Studio loading a model is expected — not a failure yet.
  if (s.id === "lm_studio" && s.readiness === "loading") return false;
  // Process up but model not loaded → targeted reload, not full restart.
  if (s.id === "lm_studio" && s.readiness === "not_ready") return true;
  if (s.readiness === "not_ready" && s.criticality === "required") return true;
  return false;
}

function diagnose(s: ServiceStatusSnapshot): DiagnosticResult {
  const evidence = [
    `process=${s.process}`,
    `health=${s.health}`,
    `readiness=${s.readiness}`,
  ];
  if (s.crashLoop) evidence.push("crash_loop=true");

  let category: DiagnosticResult["category"] = "unknown";
  let probableCause = "Cause inconnue";
  let recommended: RepairAction["type"][] = ["restart_service"];

  if (s.crashLoop) {
    category = "crash_loop";
    probableCause = "Redémarrages répétés — circuit ouvert";
    recommended = [];
  } else if (s.id === "docker" && s.health === "unhealthy") {
    category = "docker_unavailable";
    probableCause = "Docker Desktop indisponible";
    recommended = ["ensure_docker", "wait_for_health"];
  } else if (
    s.id === "searxng" &&
    (s.process === "stopped" || s.health === "unhealthy")
  ) {
    category = "container_stopped";
    probableCause = "Conteneur SearXNG arrêté ou hors service";
    recommended = ["start_docker_container", "wait_for_health"];
  } else if (s.id === "lm_studio" && s.process === "stopped") {
    category = "lm_studio_unreachable";
    probableCause = "LM Studio n’est pas démarré";
    recommended = [
      "start_service",
      "wait_for_health",
      "reload_model",
      "wait_for_readiness",
    ];
  } else if (s.id === "lm_studio" && s.readiness === "not_ready") {
    category = "model_not_loaded";
    probableCause = "Serveur LM joignable mais modèle non prêt";
    recommended = ["reload_model", "wait_for_readiness"];
  } else if (s.id === "cloudflared" && s.health === "unhealthy") {
    category = "tunnel_disconnected";
    probableCause = "Tunnel Cloudflare déconnecté";
    recommended = ["refresh_tunnel", "wait_for_health"];
  } else if (s.id === "nextjs" && s.health === "unhealthy") {
    category = "health_down";
    probableCause = "Chatbot (Next.js) ne répond plus";
    recommended = ["restart_service", "wait_for_health"];
  } else if (s.process === "stopped") {
    category = "process_absent";
    probableCause = `${s.humanName} n’est pas démarré`;
    recommended = ["start_service", "wait_for_health"];
  } else if (s.health === "unhealthy") {
    category = "health_down";
    probableCause = `${s.humanName} ne répond pas aux contrôles`;
    recommended = ["restart_service", "wait_for_health"];
  }

  return {
    incidentId: `inc-${randomUUID().slice(0, 8)}`,
    serviceId: s.id,
    category,
    severity: s.criticality === "required" ? "critical" : "degraded",
    evidence,
    probableCause,
    recommendedRepair: recommended,
    confidence: category === "unknown" ? 0.4 : 0.85,
    timestamp: new Date().toISOString(),
  };
}

export function buildMinimalRepairPlan(
  services: ServiceStatusSnapshot[],
  opts?: { onlyServiceId?: string }
): RepairPlan {
  const byId = new Map(services.map((s) => [s.id, s]));
  let targets = services.filter(isDown);

  if (opts?.onlyServiceId) {
    const t = opts.onlyServiceId;
    targets = targets.filter((s) => s.id === t);
    for (const s of services) {
      if (s.id !== t && isDown(s) && dependsOn(t, s.id)) targets.push(s);
    }
  }

  const expanded = new Map<string, ServiceStatusSnapshot>();
  for (const t of targets) {
    expanded.set(t.id, t);
    for (const def of SERVICE_REGISTRY) {
      if (!dependsOn(t.id, def.id)) continue;
      const dep = byId.get(def.id);
      if (dep && isDown(dep)) expanded.set(def.id, dep);
    }
  }

  const diagnosis = [...expanded.values()].map(diagnose);
  const ordered = [...expanded.values()].sort((a, b) => {
    if (dependsOn(a.id, b.id)) return 1;
    if (dependsOn(b.id, a.id)) return -1;
    return 0;
  });

  const actions: RepairAction[] = [];
  for (const s of ordered) {
    if (s.crashLoop) continue;
    const diag = diagnosis.find((d) => d.serviceId === s.id)!;
    for (const type of diag.recommendedRepair) {
      actions.push({ type, serviceId: s.id, reason: diag.probableCause });
    }
  }

  const targetServiceIds = ordered.map((s) => s.id);
  const untouchedServiceIds = services
    .map((s) => s.id)
    .filter((id) => !targetServiceIds.includes(id));

  return {
    planId: `plan-${randomUUID().slice(0, 8)}`,
    incidentId: diagnosis[0]?.incidentId ?? `inc-${randomUUID().slice(0, 8)}`,
    targetServiceIds,
    untouchedServiceIds,
    actions,
    diagnosis,
    createdAt: new Date().toISOString(),
  };
}

/** Alias — same minimal blast-radius planner. */
export const buildRepairPlan = buildMinimalRepairPlan;

export function summarizePlanForUser(plan: RepairPlan): string {
  if (plan.actions.length === 0) {
    if (plan.diagnosis.some((d) => d.category === "crash_loop")) {
      return "Un service est instable (trop de redémarrages). Réessaie plus tard.";
    }
    return "Aucun problème à réparer.";
  }
  const names = plan.targetServiceIds
    .map((id) => getServiceDefinition(id)?.humanName ?? id)
    .join(", ");
  return `Réparation ciblée : ${names}. Les autres services ne seront pas touchés.`;
}

export function computeOverallState(
  services: ServiceStatusSnapshot[],
  repairing: boolean
): OverallState {
  if (repairing) return "recovering";
  const requiredDown = services.some(
    (s) =>
      s.criticality === "required" &&
      (s.health === "unhealthy" || s.process === "stopped" || s.crashLoop)
  );
  if (requiredDown) return "error";
  const optionalDown = services.some(
    (s) =>
      s.criticality === "optional" &&
      (s.health === "unhealthy" ||
        s.process === "stopped" ||
        (s.id === "lm_studio" && s.readiness === "not_ready"))
  );
  if (optionalDown) return "degraded";
  return "healthy";
}

export function humanOverallMessage(
  state: OverallState,
  services: ServiceStatusSnapshot[]
): string {
  switch (state) {
    case "healthy":
      return "Tout est opérationnel";
    case "recovering":
      return "Réparation en cours…";
    case "offline":
      return "PC hors ligne";
    case "error": {
      const down = services.find(
        (s) =>
          s.criticality === "required" &&
          (s.health === "unhealthy" || s.process === "stopped")
      );
      return down
        ? `${down.humanName} nécessite une attention`
        : "Un problème critique a été détecté";
    }
    case "degraded": {
      const down = services.find(
        (s) =>
          s.criticality === "optional" &&
          (s.health === "unhealthy" ||
            s.process === "stopped" ||
            s.readiness === "not_ready")
      );
      return down
        ? `${down.humanName} indisponible`
        : "Fonctionnement dégradé";
    }
  }
}
