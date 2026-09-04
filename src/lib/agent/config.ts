import type { AppSettings } from "@/lib/settings/service";
import type { AgentLimits } from "./types";

/** Limites techniques de l'orchestrateur — configurables dans Paramètres avancés. */
export function resolveAgentLimits(settings: AppSettings): AgentLimits {
  return {
    maxSteps: settings.agentMaxStepsStandard,
    maxToolCalls: settings.agentMaxToolCalls,
    maxExecutionTimeMs: settings.agentMaxExecutionTimeMs,
  };
}

export function getModeLabel(mode: "chat" | "agent"): string {
  return mode === "agent" ? "Agent" : "Chat";
}
