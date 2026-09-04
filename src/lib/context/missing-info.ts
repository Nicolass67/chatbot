/**
 * Domain-agnostic missing-information handling.
 * No hard-coded business domains (marge/prix/…).
 * Principle: never invent a missing quantitative value.
 */

export type MissingInfoHint = {
  /** Inject into system as soft constraint */
  systemNote: string;
  /** Optional short user-facing clarification if we choose to ask */
  askUser?: string;
};

const QUANT_TASK_RE =
  /\b(calcul|calcule|calculer|somme|total|moyenne|pourcentage|ratio|quantit|combien|nombre|montant|co[uû]t|budget|prix|marge|b[eé]n[eé]fice)\b/i;

/**
 * Conservative detector: only flags likely quantitative tasks.
 * Does not invent required slot names per domain.
 */
export function detectQuantitativeTask(message: string): boolean {
  return QUANT_TASK_RE.test(message);
}

/**
 * If the task looks quantitative and context has no numeric literals,
 * remind the model not to invent numbers.
 */
export function buildMissingInfoHint(input: {
  userMessage: string;
  contextText: string;
}): MissingInfoHint | null {
  if (!detectQuantitativeTask(input.userMessage)) return null;

  const hasNumber = /\d/.test(input.contextText) || /\d/.test(input.userMessage);
  if (hasNumber) return null;

  return {
    systemNote: `<missing_information_policy>
La demande semble quantitative, mais aucune valeur numérique n'est présente dans le contexte fourni.
N'invente AUCUNE valeur numérique manquante.
Demande à l'utilisateur les données manquantes, ou indique clairement toute hypothèse avant de calculer.
</missing_information_policy>`,
    askUser:
      "Pour calculer précisément, il me manque des valeurs numériques. Peux-tu les indiquer ?",
  };
}
