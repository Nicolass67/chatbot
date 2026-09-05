import { randomUUID } from "node:crypto";
import {
  emptyInfrastructureStatus,
  enqueueSupervisorCommand,
  readIncidents,
  readInfrastructureStatus,
  readLastRepair,
} from "./status-store";
import {
  buildMinimalRepairPlan,
  computeOverallState,
  humanOverallMessage,
  summarizePlanForUser,
} from "./repair-planner";
import { SERVICE_REGISTRY } from "./service-registry";
import type { InfrastructureStatus, ServiceStatusSnapshot } from "./types";

export const SUPERVISOR_URL =
  process.env.CHATBOT_SUPERVISOR_URL || "http://127.0.0.1:3927";

export async function fetchSupervisorStatus(): Promise<InfrastructureStatus | null> {
  try {
    const res = await fetch(`${SUPERVISOR_URL}/status`, {
      signal: AbortSignal.timeout(2500),
      cache: "no-store",
    });
    if (!res.ok) return null;
    return (await res.json()) as InfrastructureStatus;
  } catch {
    return null;
  }
}

export function normalizeStatus(
  raw: InfrastructureStatus | null
): InfrastructureStatus {
  if (!raw) {
    const file = readInfrastructureStatus();
    if (file) return file;
    return emptyInfrastructureStatus(
      "Supervisor hors ligne — le PC peut être éteint ou le service non démarré"
    );
  }

  const services = (raw.services || []).map((s) => ({
    ...s,
    displayName: s.displayName || s.humanName,
    humanName: s.humanName || s.displayName,
  })) as ServiceStatusSnapshot[];

  const overallState =
    raw.overallState ||
    computeOverallState(services, Boolean(raw.activeRepairId));

  return {
    overallState,
    powerState: raw.powerState || "online",
    generatedAt: raw.generatedAt || new Date().toISOString(),
    supervisorAlive: raw.supervisorAlive !== false,
    message: raw.message || humanOverallMessage(overallState, services),
    services:
      services.length > 0
        ? services
        : SERVICE_REGISTRY.map((d) => ({
            id: d.id,
            displayName: d.displayName,
            humanName: d.humanName,
            category: d.category,
            criticality: d.criticality,
            process: "unknown" as const,
            health: "unknown" as const,
            readiness: "unknown" as const,
            summary: "En attente du Supervisor",
            lastCheckAt: null,
            lastRecoveryAt: null,
            restartCount: 0,
            incidentId: null,
            crashLoop: false,
          })),
    activeRepairId: raw.activeRepairId ?? null,
  };
}

export async function getNormalizedInfrastructureStatus() {
  return normalizeStatus(await fetchSupervisorStatus());
}

export async function requestSupervisorRepair(serviceId?: string) {
  try {
    const res = await fetch(`${SUPERVISOR_URL}/repair`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(serviceId ? { serviceId } : {}),
      signal: AbortSignal.timeout(180_000),
    });
    if (res.ok) return await res.json();
  } catch {
    // fall through to command file
  }

  enqueueSupervisorCommand({
    type: serviceId ? "repair_service" : "repair",
    serviceId,
    requestId: `req-${randomUUID().slice(0, 10)}`,
  });

  return {
    status: "queued",
    message: "Commande de réparation envoyée au Supervisor",
  };
}

export function planFromStatus(
  status: InfrastructureStatus,
  serviceId?: string
) {
  const plan = buildMinimalRepairPlan(status.services, {
    onlyServiceId: serviceId,
  });
  return { plan, summary: summarizePlanForUser(plan) };
}

export function listIncidents() {
  return readIncidents();
}

export function lastRepair() {
  return readLastRepair();
}
