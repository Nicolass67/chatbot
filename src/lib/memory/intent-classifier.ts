import { z } from "zod";
import { memoryCategorySchema } from "@/lib/settings/service";
import type { ObjectiveContext } from "@/lib/request-router/types";
import { coerceMemoryItems } from "./normalize-items";

export const memoryIntentClassificationSchema = z.object({
  shouldRemember: z.boolean(),
  memories: z
    .array(
      z.object({
        content: z.string().min(10),
        category: memoryCategorySchema,
        importance: z.number().min(0).max(1),
      })
    )
    .default([]),
  confidence: z.number().min(0).max(1),
  reason: z.string().min(1),
});

export type MemoryIntentClassification = z.infer<
  typeof memoryIntentClassificationSchema
>;

export type MemoryIntentSource =
  | "disabled"
  | "none"
  | "fast_path"
  | "llm_classifier";

export interface MemoryIntentDecision {
  shouldRemember: boolean;
  memories: MemoryIntentClassification["memories"];
  confidence: number;
  source: MemoryIntentSource;
  reason: string;
  latencyMs: number;
}

function extractJsonFromContent(content: string): unknown {
  const trimmed = content.trim();
  const fenceMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
  const jsonStr = fenceMatch ? fenceMatch[1].trim() : trimmed;
  const start = jsonStr.indexOf("{");
  const end = jsonStr.lastIndexOf("}");
  if (start === -1 || end === -1) {
    throw new Error("Réponse mémoire sans JSON valide");
  }
  return JSON.parse(jsonStr.slice(start, end + 1));
}

export function parseMemoryIntentClassification(content: string) {
  const raw = extractJsonFromContent(content);
  if (!raw || typeof raw !== "object") {
    throw new Error("Réponse mémoire JSON invalide");
  }
  const obj = raw as Record<string, unknown>;
  const memories = coerceMemoryItems(obj.memories);
  const shouldRemember =
    typeof obj.shouldRemember === "boolean"
      ? obj.shouldRemember
      : memories.length > 0;
  const confidence =
    typeof obj.confidence === "number" && Number.isFinite(obj.confidence)
      ? obj.confidence
      : shouldRemember
        ? 0.85
        : 0.5;
  const reason =
    typeof obj.reason === "string" && obj.reason.trim()
      ? obj.reason.trim()
      : shouldRemember
        ? "Fait personnel détecté"
        : "Rien à mémoriser";

  return memoryIntentClassificationSchema.parse({
    shouldRemember: shouldRemember || memories.length > 0,
    memories,
    confidence,
    reason,
  });
}
export function buildMemoryClassifierSystemPrompt(): string {
  return `Tu es un analyseur de mémoire long terme pour un chatbot local. Tu ne réponds PAS à l'utilisateur.

Tu produis UNIQUEMENT un objet JSON valide, sans markdown ni texte autour.

Objectif: décider toi-même si le message contient une information PERSONNELLE durable utile pour les conversations futures. Aucune règle lexicale figée — juge le sens.

Mémoriser si pertinent (faits stables sur l'utilisateur):
- identité / démographie: âge, prénom ou surnom, ville/région, métier, situation familiale
- préférences explicites (langage, outils, style de réponse)
- matériel / config perso (PC, GPU, OS, stack)
- projet en cours, contraintes récurrentes
- habitudes de travail, contexte pro/perso stable
- demandes explicites de mémorisation

NE PAS mémoriser:
- questions ponctuelles sans info personnelle durable
- faits encyclopédiques ou actualité
- bavardage sans intérêt futur
- secrets sensibles (mots de passe, tokens, numéros de carte, données bancaires)

Si shouldRemember=true, extrais 1 à 3 faits concis formulés à la 3e personne, ≥10 caractères chacun.
Exemples de formulation: "L'utilisateur a 26 ans", "L'utilisateur s'appelle Nicolas", "Préfère les réponses concises".
Catégorie: identity → "other" ; préférences → "preference" ; etc. Importance ≥ 0.7 pour les faits d'identité.

JSON attendu:
{
  "shouldRemember": false,
  "memories": [{ "content": "...", "category": "preference|hardware|project|habit|communication|other", "importance": 0.0-1.0 }],
  "confidence": 0.0,
  "reason": "..."
}`;
}

export function buildMemoryClassifierUserPrompt(objective: ObjectiveContext): string {
  const lines = [
    `Message utilisateur:\n${objective.trimmedMessage}`,
    `Mode: ${objective.chatMode}`,
  ];

  if (objective.conversationalContext) {
    lines.push(`Contexte récent:\n${objective.conversationalContext}`);
  }

  lines.push("Y a-t-il une information à mémoriser ?");
  return lines.join("\n\n");
}
