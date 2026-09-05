import { describe, expect, it } from "vitest";
import {
  buildMinimalRepairPlan,
  buildRepairPlan,
  computeOverallState,
  humanOverallMessage,
  summarizePlanForUser,
} from "./repair-planner";
import type { ServiceStatusSnapshot } from "./types";

function snap(
  partial: Partial<ServiceStatusSnapshot> & Pick<ServiceStatusSnapshot, "id">
): ServiceStatusSnapshot {
  const defaults: Record<string, Partial<ServiceStatusSnapshot>> = {
    docker: {
      displayName: "Docker",
      humanName: "Moteur conteneurs",
      category: "platform",
      criticality: "optional",
    },
    searxng: {
      displayName: "SearXNG",
      humanName: "Recherche Web",
      category: "search",
      criticality: "optional",
    },
    nextjs: {
      displayName: "Chatbot",
      humanName: "Chatbot",
      category: "core",
      criticality: "required",
    },
    lm_studio: {
      displayName: "LM Studio",
      humanName: "Assistant IA",
      category: "ai",
      criticality: "optional",
    },
    cloudflared: {
      displayName: "Tunnel",
      humanName: "Connexion distante",
      category: "ingress",
      criticality: "optional",
    },
  };
  const base = defaults[partial.id] ?? {
    displayName: partial.id,
    humanName: partial.id,
    category: "core" as const,
    criticality: "optional" as const,
  };
  return {
    process: "running",
    health: "healthy",
    readiness: "ready",
    summary: "ok",
    lastCheckAt: new Date().toISOString(),
    lastRecoveryAt: null,
    restartCount: 0,
    incidentId: null,
    crashLoop: false,
    ...base,
    ...partial,
  } as ServiceStatusSnapshot;
}

function allHealthy(): ServiceStatusSnapshot[] {
  return ["docker", "searxng", "nextjs", "lm_studio", "cloudflared"].map((id) =>
    snap({ id })
  );
}

describe("buildMinimalRepairPlan", () => {
  it("all healthy → empty actions", () => {
    const plan = buildMinimalRepairPlan(allHealthy());
    expect(plan.actions).toEqual([]);
    expect(plan.targetServiceIds).toEqual([]);
    expect(summarizePlanForUser(plan)).toMatch(/Aucun problème/i);
  });

  it("searxng down only → only searxng (+ docker if down)", () => {
    const services = allHealthy().map((s) =>
      s.id === "searxng"
        ? snap({
            id: "searxng",
            process: "stopped",
            health: "unhealthy",
            readiness: "not_ready",
          })
        : s
    );
    const plan = buildMinimalRepairPlan(services);
    expect(plan.targetServiceIds).toEqual(["searxng"]);
    expect(plan.actions.every((a) => a.serviceId === "searxng")).toBe(true);
    expect(plan.actions.some((a) => a.type === "start_docker_container")).toBe(
      true
    );
  });

  it("nextjs down, searxng healthy → nextjs only", () => {
    const services = allHealthy().map((s) =>
      s.id === "nextjs"
        ? snap({
            id: "nextjs",
            health: "unhealthy",
            readiness: "not_ready",
          })
        : s
    );
    const plan = buildMinimalRepairPlan(services);
    expect(plan.targetServiceIds).toEqual(["nextjs"]);
    expect(plan.untouchedServiceIds).toContain("searxng");
    expect(plan.actions.every((a) => a.serviceId === "nextjs")).toBe(true);
  });

  it("docker+searxng down → docker before searxng", () => {
    const services = allHealthy().map((s) => {
      if (s.id === "docker") {
        return snap({
          id: "docker",
          process: "stopped",
          health: "unhealthy",
          readiness: "not_ready",
        });
      }
      if (s.id === "searxng") {
        return snap({
          id: "searxng",
          process: "stopped",
          health: "unhealthy",
          readiness: "not_ready",
        });
      }
      return s;
    });
    const plan = buildMinimalRepairPlan(services);
    expect(plan.targetServiceIds).toEqual(["docker", "searxng"]);
    const firstDocker = plan.actions.findIndex((a) => a.serviceId === "docker");
    const firstSearx = plan.actions.findIndex((a) => a.serviceId === "searxng");
    expect(firstDocker).toBeGreaterThanOrEqual(0);
    expect(firstSearx).toBeGreaterThan(firstDocker);
  });

  it("crashLoop → no restart actions", () => {
    const services = allHealthy().map((s) =>
      s.id === "nextjs"
        ? snap({
            id: "nextjs",
            health: "unhealthy",
            crashLoop: true,
          })
        : s
    );
    const plan = buildMinimalRepairPlan(services);
    expect(plan.diagnosis.some((d) => d.category === "crash_loop")).toBe(true);
    expect(plan.actions).toEqual([]);
    expect(summarizePlanForUser(plan)).toMatch(/instable|redémarrages/i);
  });

  it("lm_studio process running readiness not_ready → reload_model not full restart", () => {
    const services = allHealthy().map((s) =>
      s.id === "lm_studio"
        ? snap({
            id: "lm_studio",
            process: "running",
            health: "healthy",
            readiness: "not_ready",
          })
        : s
    );
    const plan = buildMinimalRepairPlan(services);
    expect(plan.targetServiceIds).toEqual(["lm_studio"]);
    const types = plan.actions.map((a) => a.type);
    expect(types).toContain("reload_model");
    expect(types).not.toContain("restart_service");
    expect(types).not.toContain("start_service");
  });

  it("buildRepairPlan is an alias of buildMinimalRepairPlan", () => {
    expect(buildRepairPlan).toBe(buildMinimalRepairPlan);
  });
});

describe("computeOverallState / humanOverallMessage", () => {
  it("healthy when all good", () => {
    const services = allHealthy();
    expect(computeOverallState(services, false)).toBe("healthy");
    expect(humanOverallMessage("healthy", services)).toMatch(/opérationnel/i);
  });

  it("recovering when repairing", () => {
    expect(computeOverallState(allHealthy(), true)).toBe("recovering");
  });

  it("error when required nextjs down", () => {
    const services = allHealthy().map((s) =>
      s.id === "nextjs"
        ? snap({ id: "nextjs", process: "stopped", health: "unhealthy" })
        : s
    );
    expect(computeOverallState(services, false)).toBe("error");
  });

  it("degraded when optional searxng down", () => {
    const services = allHealthy().map((s) =>
      s.id === "searxng"
        ? snap({ id: "searxng", process: "stopped", health: "unhealthy" })
        : s
    );
    expect(computeOverallState(services, false)).toBe("degraded");
  });
});
