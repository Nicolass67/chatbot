import { nanoid } from "nanoid";
import { getLocalAIRuntime } from "@/lib/runtime/factory";
import {
  memoryDecisionPayloadSchema,
  type MemoryDecisionPayload,
  type MemoryPostProcessorInput,
} from "./types";

function extractJsonObject(raw: string): unknown {
  const trimmed = raw.trim();
  const fence = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
  const body = fence ? fence[1].trim() : trimmed;
  const start = body.indexOf("{");
  const end = body.lastIndexOf("}");
  if (start < 0 || end <= start) {
    throw new Error("Réponse mémoire sans objet JSON");
  }
  return JSON.parse(body.slice(start, end + 1));
}

export function buildMemoryDecisionSystemPrompt(): string {
  return `Tu es un Memory Post-Processor. Tu n'es PAS l'assistant conversationnel.
Tu analyses un échange déjà terminé et tu décides si des souvenirs long terme doivent être créés, mis à jour, ou supprimés.

Tu produis UNIQUEMENT un objet JSON valide, sans markdown ni texte autour.

But: retenir uniquement les informations PERSONNELLES ou opérationnelles utiles pour de futures conversations.
Privilégier la valeur future, pas le volume.

Mémoriser typiquement:
- préférences explicites durables
- faits d'identité stables (âge, prénom, ville, métier…)
- changements de vie durables (déménagement, nouveau poste…)
- workflows / outils préférés récurrents
- projets en cours / contraintes persistantes

Ne PAS mémoriser:
- questions ponctuelles
- trivia du jour (faim, météo, courses)
- hypothèses
- secrets (mots de passe, tokens, cartes, données bancaires)
- détails d'une tâche temporaire sans utilité future

Gestion des souvenirs existants:
- Si une nouvelle info contredit ou précise un souvenir existant → action "update" avec existingMemoryId
- Si doublon exact ou quasi exact → action "ignore"
- Si info obsolète remplacée → "update" (préféré) ou "delete" si plus aucune valeur
- Ne jamais créer un second souvenir contradictoire

confidence:
- >= 0.90 : fort
- 0.70–0.89 : raisonnable
- < 0.70 : ignore (action "ignore")

JSON strict:
{
  "candidates": [
    {
      "action": "create|update|delete|ignore",
      "memoryType": "preference|fact|workflow|project|context|other",
      "content": "fait à la 3e personne, >= 10 caractères",
      "existingMemoryId": null,
      "confidence": 0.0,
      "reason": "courte justification"
    }
  ]
}

Si rien à faire: {"candidates":[]}`;
}

export function buildMemoryDecisionUserPrompt(
  input: MemoryPostProcessorInput
): string {
  const lines: string[] = [];
  lines.push(`Message utilisateur:\n${input.userMessage.trim()}`);
  lines.push(`Réponse assistant:\n${input.assistantMessage.trim()}`);

  if (input.recentTurns && input.recentTurns.length > 0) {
    const ctx = input.recentTurns
      .map((t) => `${t.role}: ${t.content.slice(0, 400)}`)
      .join("\n");
    lines.push(`Contexte récent (limité):\n${ctx}`);
  }

  if (input.existingMemories && input.existingMemories.length > 0) {
    const mem = input.existingMemories
      .map((m) => `- id=${m.id} [${m.category}] ${m.content}`)
      .join("\n");
    lines.push(`Souvenirs existants pertinents:\n${mem}`);
  } else {
    lines.push("Souvenirs existants pertinents:\n(aucun)");
  }

  lines.push("Décide create/update/delete/ignore. JSON uniquement.");
  return lines.join("\n\n");
}

export async function requestMemoryDecision(
  input: MemoryPostProcessorInput
): Promise<MemoryDecisionPayload> {
  const runtime = getLocalAIRuntime();
  const response = await runtime.chat({
    requestId: nanoid(),
    model: input.modelId,
    messages: [
      { role: "system", content: buildMemoryDecisionSystemPrompt() },
      { role: "user", content: buildMemoryDecisionUserPrompt(input) },
    ],
    temperature: 0,
    maxTokens: 700,
    signal: input.signal,
    reasoningEffort: "none",
  });

  const raw = extractJsonObject(response.content ?? "");
  return memoryDecisionPayloadSchema.parse(raw);
}
