import type { AppSettings } from "@/lib/settings/service";

/** Plancher de tokens pour la réponse finale Agent (évite les réponses tronquées). */
export const SYNTHESIS_MIN_MAX_TOKENS = 4096;

export function resolveSynthesisMaxTokens(settings: AppSettings): number {
  return Math.max(settings.maxTokens, SYNTHESIS_MIN_MAX_TOKENS);
}

/** Détecte une réponse probablement coupée avant la fin. */
export function looksTruncated(text: string): boolean {
  const trimmed = text.trimEnd();
  if (trimmed.length < 280) return false;
  if (/```[\s\S]*$/.test(trimmed) && !/```\s*$/.test(trimmed)) return true;
  return !/[.!?…»")\]]\s*$/.test(trimmed);
}

export function buildSynthesisContinuationMessages(
  baseMessages: Array<{ role: "system" | "user" | "assistant"; content: string }>,
  partialContent: string
): Array<{ role: "system" | "user" | "assistant"; content: string }> {
  return [
    ...baseMessages,
    { role: "assistant", content: partialContent },
    {
      role: "user",
      content:
        "Continue exactement où tu t'es arrêté. Ne répète pas le début. Termine la réponse (comparaison structurée en listes, recommandation finale et sources). N'utilise pas de tableaux markdown.",
    },
  ];
}
