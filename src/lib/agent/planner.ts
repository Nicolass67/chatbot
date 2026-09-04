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

  const steps: PlanStep[] = goalAwareFallbackSteps(goal);
  return { steps };
}

/** Plans concrets selon l’intention — évite « Comprendre la demande » générique. */
function goalAwareFallbackSteps(goal: string): PlanStep[] {
  const g = goal.toLowerCase();

  // Produit / web EN PREMIER — « carte graphique » ne doit JAMAIS matcher des étapes fichiers.
  if (isProductOrWebGoal(g)) {
    return [
      { id: "step-1", title: "Recherche web des sources actuelles", status: "active", actions: [] },
      { id: "step-2", title: "Comparer les options pertinentes", status: "pending", actions: [] },
      { id: "step-3", title: "Recommander avec sources", status: "pending", actions: [] },
    ];
  }

  // Fichiers / CI — motifs explicites seulement (pas le mot « carte » seul).
  if (isFilesGoal(g)) {
    return [
      { id: "step-1", title: "Chercher le fichier demandé", status: "active", actions: [] },
      { id: "step-2", title: "Vérifier le chemin et les droits", status: "pending", actions: [] },
      { id: "step-3", title: "Présenter le document trouvé", status: "pending", actions: [] },
    ];
  }

  if (isMailGoal(g)) {
    return [
      { id: "step-1", title: "Lire le mail concerné", status: "active", actions: [] },
      { id: "step-2", title: "Préparer le brouillon ou le résumé", status: "pending", actions: [] },
      { id: "step-3", title: "Finaliser pour validation", status: "pending", actions: [] },
    ];
  }

  return [
    { id: "step-1", title: "Analyser la demande", status: "active", actions: [] },
    { id: "step-2", title: "Collecter les infos utiles", status: "pending", actions: [] },
    { id: "step-3", title: "Formuler la réponse", status: "pending", actions: [] },
  ];
}

function isProductOrWebGoal(g: string): boolean {
  if (/\b(gpu|rtx|radeon|geforce|nvidia|amd)\b/.test(g)) return true;
  if (g.includes("carte graphique")) return true;
  if (
    (g.includes("moins de") || g.includes("prix") || g.includes("acheter") || g.includes("compar")) &&
    (g.includes("€") || g.includes("euro") || g.includes("puissance") || g.includes("budget"))
  ) {
    return true;
  }
  if (
    /\b(cherche|trouve|trouver)\b/.test(g) &&
    (g.includes("€") || g.includes("euro") || g.includes("web") || g.includes("internet"))
  ) {
    return true;
  }
  if (
    g.includes("meilleur") &&
    (g.includes("€") ||
      g.includes("euro") ||
      g.includes("puissance") ||
      g.includes("graphique") ||
      g.includes("gpu"))
  ) {
    return true;
  }
  if (g.includes("recherche web") || g.includes("sur internet") || g.includes("sur le web")) {
    return true;
  }
  if (
    (g.includes("recherche") || g.includes("internet") || /\bweb\b/.test(g)) &&
    !isFilesGoal(g) &&
    !isMailGoal(g)
  ) {
    return true;
  }
  return false;
}

function isFilesGoal(g: string): boolean {
  return (
    g.includes("fichier") ||
    g.includes("dossier") ||
    g.includes("pdf") ||
    g.includes("document") ||
    g.includes("carte d'identité") ||
    g.includes("carte d’identité") ||
    g.includes("carte nationale") ||
    g.includes("pièce d'identité") ||
    g.includes("piece d'identite") ||
    /\bci\b/.test(g) ||
    ((g.includes("identité") || g.includes("identite")) &&
      (g.includes("trouv") || g.includes("cherche") || g.includes("où") || g.includes("ou est")))
  );
}

function isMailGoal(g: string): boolean {
  return (
    /\b(mail|email|gmail|brouillon|destinataire)\b/.test(g) ||
    g.includes("répond") ||
    g.includes("repond") ||
    g.includes("courriel")
  );
}

const FILEISH_STEP =
  /fichier|dossier|chemin et les droits|document trouvé|pièce d'identité|carte d'identité|pathguard|filesystem/i;
const MAILISH_STEP = /\b(mail|brouillon|destinataire|boîte mail|boite mail)\b/i;

/** Remplace un plan LLM incohérent (ex. étapes fichiers pour une question GPU). */
export function sanitizeAgentPlan(goal: string, plan: AgentPlan): AgentPlan {
  const g = goal.toLowerCase();
  const titles = plan.steps.map((s) => s.title).join(" ");
  const expected = goalAwareFallbackSteps(goal);

  if (FILEISH_STEP.test(titles)) {
    if (isProductOrWebGoal(g) || (!isFilesGoal(g) && !g.includes("fichier") && !g.includes("dossier"))) {
      return { steps: expected };
    }
  }
  if (MAILISH_STEP.test(titles) && isProductOrWebGoal(g) && !isMailGoal(g)) {
    return { steps: expected };
  }
  return plan;
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
      return sanitizeAgentPlan(input.goal, parsePlanDraft(response.content));
    } catch {
      return fallbackPlan(input.goal, input.temporalContext);
    }
  } catch (error) {
    if (input.signal?.aborted) throw error;
    return fallbackPlan(input.goal, input.temporalContext);
  }
}

export { fallbackPlan, goalAwareFallbackSteps };
