import { nanoid } from "nanoid";
import type { LocalAIRuntime } from "@/lib/runtime/types";
import type { AppSettings } from "@/lib/settings/service";
import {
  buildPlannerSystemPrompt,
  buildPlannerUserPrompt,
} from "./prompts";
import type { TemporalContext } from "./temporal";
import { resolveEffectiveScope } from "./temporal";
import {
  agentPlanDraftSchema,
  type AgentPlan,
  type PlanStep,
} from "./types";

export interface PlannerInput {
  goal: string;
  contextHint?: string;
  temporalContext: TemporalContext;
  runtime: LocalAIRuntime;
  model: string;
  settings: AppSettings;
  reasoningEffort: string | null;
  signal?: AbortSignal;
  registerRequestId?: (id: string) => void;
}

function extractJsonFromContent(content: string): unknown {
  const trimmed = content.trim();
  const fenceMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
  const jsonStr = fenceMatch ? fenceMatch[1].trim() : trimmed;
  const start = jsonStr.indexOf("{");
  const end = jsonStr.lastIndexOf("}");
  if (start === -1 || end === -1) {
    throw new Error("Réponse planner sans JSON valide");
  }
  return JSON.parse(jsonStr.slice(start, end + 1));
}

function fallbackPlan(goal: string, temporal?: TemporalContext): AgentPlan {
  const effectiveScope = temporal ? resolveEffectiveScope(temporal) : null;
  const isMarketCurrent =
    temporal &&
    (effectiveScope === "current" || effectiveScope === "recent") &&
    temporal.isTimeSensitive;

  if (isMarketCurrent) {
    return {
      steps: [
        {
          id: "step-1",
          title: "Découverte du marché actuel",
          status: "active",
          actions: [],
        },
        {
          id: "step-2",
          title: "Analyse et comparaison des options",
          status: "pending",
          actions: [],
        },
        {
          id: "step-3",
          title: "Recommandation finale",
          status: "pending",
          actions: [],
        },
      ],
    };
  }

  const steps: PlanStep[] = [
    { id: "step-1", title: "Comprendre la demande", status: "active", actions: [] },
    { id: "step-2", title: "Rechercher des informations", status: "pending", actions: [] },
    { id: "step-3", title: "Analyser les résultats", status: "pending", actions: [] },
    { id: "step-4", title: "Rédiger la réponse", status: "pending", actions: [] },
  ];
  return { steps };
}

export function parsePlanDraft(content: string): AgentPlan {
  try {
    const raw = extractJsonFromContent(content);
    const draft = agentPlanDraftSchema.parse(raw);
    return {
      steps: draft.steps.map((s, i) => ({
        id: s.id,
        title: s.title,
        status: i === 0 ? "active" : "pending",
        actions: [],
      })),
    };
  } catch {
    throw new Error("Plan invalide");
  }
}

export async function createAgentPlan(input: PlannerInput): Promise<AgentPlan> {
  const requestId = nanoid();
  input.registerRequestId?.(requestId);

  try {
    const response = await input.runtime.chat({
      requestId,
      model: input.model,
      messages: [
        { role: "system", content: buildPlannerSystemPrompt(input.temporalContext) },
        {
          role: "user",
          content: buildPlannerUserPrompt(
            input.goal,
            input.temporalContext,
            input.contextHint
          ),
        },
      ],
      temperature: 0.3,
      maxTokens: 1024,
      signal: input.signal,
      reasoningEffort: null,
    });

    if (!response.content?.trim()) {
      return fallbackPlan(input.goal, input.temporalContext);
    }

    try {
      return parsePlanDraft(response.content);
    } catch {
      return fallbackPlan(input.goal, input.temporalContext);
    }
  } catch (error) {
    if (input.signal?.aborted) throw error;
    return fallbackPlan(input.goal, input.temporalContext);
  }
}

export { fallbackPlan };
