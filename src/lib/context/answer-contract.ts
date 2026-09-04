/**
 * Short answer contracts — complement RESPONSE_FORMAT, not a second system prompt.
 */
import type { AnswerContract } from "@/lib/context/plan";

export function answerContractInstructions(
  contract: AnswerContract
): string | null {
  switch (contract) {
    case "sourced":
      return `<answer_contract type="sourced">
Réponds avec les faits supportés par les sources fournies. Cite les URLs quand disponibles. Si les sources divergent, dis-le brièvement. N'invente pas de chiffres absents des sources.
</answer_contract>`;
    case "personal":
      return `<answer_contract type="personal">
Adapte la réponse aux préférences / faits utilisateur présents dans <memory> ou <active_context>. Ne force pas de personnalisation si aucune donnée pertinente n'est disponible.
</answer_contract>`;
    case "action":
      return `<answer_contract type="action">
Sois concret : propose l'action, le résultat attendu, et demande confirmation si une mutation est requise. Ne prétends pas avoir exécuté une action non confirmée.
</answer_contract>`;
    case "plain":
    default:
      return null;
  }
}
