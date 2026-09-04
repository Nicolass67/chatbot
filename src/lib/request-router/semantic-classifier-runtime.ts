import { nanoid } from "nanoid";
import {
  buildClassifierSystemPrompt,
  buildClassifierUserPrompt,
  parseSemanticClassification,
} from "./semantic-classifier";
import type { ObjectiveContext, RequestContext, SemanticClassification } from "./types";

export const CLASSIFIER_TIMEOUT_MS = 5_000;
export const CLASSIFIER_MAX_TOKENS = 180;

/** Seuil calibré sur le dataset — préfère accepter une décision claire du modèle. */
export const CLASSIFIER_ACCEPT_CONFIDENCE = 0.72;

export function shouldUseSemanticClassifier(ctx: RequestContext): boolean {
  if (process.env.ROUTER_DISABLE_LLM_CLASSIFIER === "1") return false;
  return Boolean(ctx.runtime && ctx.modelId);
}

export async function classifySemantic(
  ctx: RequestContext,
  objective: ObjectiveContext
): Promise<SemanticClassification> {
  if (!ctx.runtime) {
    throw new Error("Runtime LLM indisponible pour le classifier");
  }

  const requestId = nanoid();
  const signal = ctx.signal ?? AbortSignal.timeout(CLASSIFIER_TIMEOUT_MS);

  const response = await ctx.runtime.chat({
    requestId,
    model: ctx.modelId,
    messages: [
      { role: "system", content: buildClassifierSystemPrompt(objective) },
      { role: "user", content: buildClassifierUserPrompt(objective) },
    ],
    temperature: 0,
    maxTokens: CLASSIFIER_MAX_TOKENS,
    signal,
    reasoningEffort: "none",
  });

  if (!response.content?.trim()) {
    throw new Error("Classifier LLM: réponse vide");
  }

  return parseSemanticClassification(response.content);
}
