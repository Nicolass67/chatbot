import type { ServiceDefinition } from "./types";

/**
 * Registry déclaratif — dépendances auditées depuis scripts/boot + docker-compose + cloudflared.
 *
 * Graph réel (scripts/boot/orchestrator.mjs, docker.mjs, lm-studio.mjs, network.mjs):
 *   docker → searxng
 *   sqlite (in-process with next) — no separate process
 *   nextjs (independent of searxng/lm for start; degraded if they fail)
 *   cloudflared → ideally nextjs listening (ingress)
 *   lm_studio — optional AI; readiness = model loaded
 */
export const SERVICE_REGISTRY: readonly ServiceDefinition[] = [
  {
    id: "docker",
    displayName: "Docker",
    humanName: "Moteur conteneurs",
    category: "platform",
    criticality: "optional",
    enabled: true,
    dependencies: [],
    optionalDependencies: [],
    healthIntervalMs: 15_000,
    healthTimeoutMs: 5_000,
    startupTimeoutMs: 120_000,
    failureThreshold: 2,
    recoveryThreshold: 1,
    maxRestarts: 3,
    restartWindowMs: 10 * 60_000,
    baseBackoffMs: 5_000,
    maxBackoffMs: 120_000,
  },
  {
    id: "searxng",
    displayName: "SearXNG",
    humanName: "Recherche Web",
    category: "search",
    criticality: "optional",
    enabled: true,
    dependencies: ["docker"],
    optionalDependencies: [],
    healthIntervalMs: 20_000,
    healthTimeoutMs: 8_000,
    startupTimeoutMs: 180_000,
    failureThreshold: 2,
    recoveryThreshold: 1,
    maxRestarts: 4,
    restartWindowMs: 15 * 60_000,
    baseBackoffMs: 4_000,
    maxBackoffMs: 90_000,
  },
  {
    id: "nextjs",
    displayName: "Chatbot",
    humanName: "Chatbot",
    category: "core",
    criticality: "required",
    enabled: true,
    dependencies: [],
    optionalDependencies: [],
    healthIntervalMs: 10_000,
    healthTimeoutMs: 5_000,
    startupTimeoutMs: 120_000,
    failureThreshold: 2,
    recoveryThreshold: 1,
    maxRestarts: 5,
    restartWindowMs: 15 * 60_000,
    baseBackoffMs: 3_000,
    maxBackoffMs: 60_000,
  },
  {
    id: "lm_studio",
    displayName: "LM Studio",
    humanName: "Assistant IA",
    category: "ai",
    criticality: "optional",
    enabled: true,
    dependencies: [],
    optionalDependencies: [],
    healthIntervalMs: 15_000,
    healthTimeoutMs: 8_000,
    startupTimeoutMs: 300_000,
    failureThreshold: 2,
    recoveryThreshold: 1,
    maxRestarts: 3,
    restartWindowMs: 20 * 60_000,
    baseBackoffMs: 8_000,
    maxBackoffMs: 180_000,
  },
  {
    id: "cloudflared",
    displayName: "Tunnel",
    humanName: "Connexion distante",
    category: "ingress",
    criticality: "optional",
    enabled: true,
    dependencies: ["nextjs"],
    optionalDependencies: [],
    healthIntervalMs: 20_000,
    healthTimeoutMs: 5_000,
    startupTimeoutMs: 60_000,
    failureThreshold: 3,
    recoveryThreshold: 1,
    maxRestarts: 4,
    restartWindowMs: 15 * 60_000,
    baseBackoffMs: 5_000,
    maxBackoffMs: 120_000,
  },
] as const;

export function getServiceDefinition(id: string): ServiceDefinition | undefined {
  return SERVICE_REGISTRY.find((s) => s.id === id);
}

export function requiredServiceIds(): string[] {
  return SERVICE_REGISTRY.filter((s) => s.criticality === "required" && s.enabled).map(
    (s) => s.id
  );
}

export function optionalServiceIds(): string[] {
  return SERVICE_REGISTRY.filter((s) => s.criticality === "optional" && s.enabled).map(
    (s) => s.id
  );
}
