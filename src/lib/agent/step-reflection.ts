import { nanoid } from "nanoid";
import type { LocalAIRuntime } from "@/lib/runtime/types";
import type { AgentExecutionContext, AgentObservation } from "./types";

export type StepReflectionInput = {
  goal: string;
  stepId: string;
  stepTitle: string;
  previousReflection?: string;
  recentObservations: Pick<AgentObservation, "tool" | "summary">[];
  runtime: LocalAIRuntime;
  model: string;
  signal?: AbortSignal;
  registerRequestId?: (id: string) => void;
};

/**
 * Réflexion courte après une étape — devient l'entrée du tour suivant.
 * Échec LLM → résumé déterministe des observations (jamais bloquant).
 */
export async function generateStepReflection(
  input: StepReflectionInput
): Promise<string> {
  const obsBlock =
    input.recentObservations.length === 0
      ? "(aucune observation)"
      : input.recentObservations
          .slice(-6)
          .map((o, i) => `${i + 1}. [${o.tool}] ${o.summary}`)
          .join("\n");

  const fallback = buildDeterministicReflection(
    input.stepTitle,
    input.previousReflection,
    input.recentObservations
  );

  const requestId = nanoid();
  input.registerRequestId?.(requestId);

  try {
    const response = await input.runtime.chat({
      requestId,
      model: input.model,
      messages: [
        {
          role: "system",
          content: `Tu es un agent qui réfléchit après une étape d'exécution.
Produis 4 à 8 phrases en français : ce qui a été appris, ce qui reste incertain, et ce que l'étape suivante doit faire concrètement.
Pas de markdown, pas de liste à puces, pas d'outil à inventer.`,
        },
        {
          role: "user",
          content: `Objectif : ${input.goal}

Étape terminée : ${input.stepTitle} (${input.stepId})

Réflexion précédente :
${input.previousReflection?.trim() || "(aucune)"}

Observations récentes :
${obsBlock}

Réflexion pour l'étape suivante :`,
        },
      ],
      temperature: 0.2,
      maxTokens: 400,
      signal: input.signal,
      reasoningEffort: "off",
    });
    const text = response.content?.trim();
    return text && text.length >= 40 ? text : fallback;
  } catch {
    return fallback;
  }
}

export function buildDeterministicReflection(
  stepTitle: string,
  previousReflection: string | undefined,
  observations: Pick<AgentObservation, "tool" | "summary">[]
): string {
  const bits = observations
    .slice(-4)
    .map((o) => o.summary)
    .filter(Boolean);
  const prev = previousReflection?.trim();
  const learned =
    bits.length > 0
      ? `Après « ${stepTitle} », points retenus : ${bits.join(" · ")}.`
      : `Étape « ${stepTitle} » clôturée sans nouveau fait outil.`;
  if (prev) {
    return `${learned} Suite de la réflexion précédente : ${prev.slice(0, 280)}`;
  }
  return `${learned} Prochaine étape : exploiter ces éléments sans relancer une recherche inutile.`;
}

/** Enregistre la réflexion dans le contexte d'exécution (chaînage). */
export function applyStepReflection(
  ctx: AgentExecutionContext,
  stepId: string,
  title: string,
  reflection: string
): void {
  const text = reflection.trim();
  if (!text) return;
  ctx.lastReflection = text;
  if (!ctx.stepReflections) ctx.stepReflections = [];
  ctx.stepReflections.push({ stepId, title, reflection: text });
  ctx.observations.push({
    tool: "step_reflection",
    stepId,
    input: { stepId, title },
    output: { reflection: text },
    summary: text.slice(0, 400),
    timestamp: new Date().toISOString(),
  });
}
