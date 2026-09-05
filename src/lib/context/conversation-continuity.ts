/**
 * Continuité conversationnelle : follow-ups anaphoriques + ancrage des requêtes web.
 */

const ANAPHORA_RE =
  /\b(ça|cela|celui|celle|ceux|celles|leur|leurs|en|y|pareil|idem|modèles?|models?|ceux[- ]là|celles[- ]là|celui[- ]là|celle[- ]là|maintenant|aussi|également|lesquels|lesquelles|lequel|laquelle|combien|dessus|ci[- ]dessus|précédent|précédente|mentionné|mentionnée|évoqué|évoquée)\b/i;

const IMPERATIVE_FOLLOW_UP_RE =
  /^(donne|dis|montre|liste|cite|compare|détaille|detaille|explique|trouve|propose|indique|sélectionne|selectionne|reprends?|continue)\b/i;

const EXPLICIT_FOLLOW_UP_RE =
  /^(et (lui|elle|eux|ça|cela|le|la|les|mon|ma|mes|celui|celle|ceux)\b|fais pareil|pareil|idem|envoie[- ]?le|vérifie(\s|$)|le deuxième|la deuxième|et pour moi)\b/i;

/** Messages utilisateur antérieurs (hors message courant déjà persisté). */
export function priorUserMessages(
  allUserMessages: string[],
  currentMessage: string
): string[] {
  const current = currentMessage.trim();
  const cleaned = allUserMessages.map((m) => m.trim()).filter(Boolean);
  if (cleaned.length === 0) return [];
  if (cleaned[cleaned.length - 1] === current) {
    return cleaned.slice(0, -1);
  }
  return cleaned;
}

export function isFollowUpTurn(
  message: string,
  hasPriorUserMessages: boolean
): boolean {
  const t = message.trim();
  if (t.length === 0) return false;
  const words = t.split(/\s+/).filter(Boolean);
  if (words.length <= 4) return true;
  if (words.length <= 8 && EXPLICIT_FOLLOW_UP_RE.test(t)) return true;
  if (!hasPriorUserMessages) return false;
  if (words.length <= 14 && ANAPHORA_RE.test(t)) return true;
  if (words.length <= 12 && IMPERATIVE_FOLLOW_UP_RE.test(t)) return true;
  return false;
}

function significantTokens(text: string): string[] {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .split(/[^a-z0-9àâäéèêëïîôùûüç]+/i)
    .map((t) => t.trim())
    .filter((t) => t.length >= 4);
}

/** Ancre une requête web avec le contexte récent si le tour est un follow-up. */
export function groundSearchQueryWithContext(params: {
  query: string;
  recentUserMessages: string[];
  force?: boolean;
}): string {
  const query = params.query.trim();
  if (!query) return query;
  const priors = params.recentUserMessages.map((m) => m.trim()).filter(Boolean);
  if (priors.length === 0) return query;

  const shouldGround = params.force === true || isFollowUpTurn(query, true);
  if (!shouldGround) return query;

  const priorText = priors.slice(-2).join(" ");
  const priorTokens = significantTokens(priorText);
  if (priorTokens.length === 0) return query;

  const queryLower = query.toLowerCase();
  const missing = priorTokens.filter((t) => !queryLower.includes(t)).slice(0, 6);
  if (missing.length === 0) return query;

  const anchor = priors[priors.length - 1]!.slice(0, 160);
  return `${query} ${anchor}`.replace(/\s+/g, " ").trim();
}

export function formatAgentConversationHistory(
  turns: Array<{ role: "user" | "assistant"; text: string }>,
  maxTurns = 6
): string {
  const cleaned = turns
    .map((t) => ({ role: t.role, text: t.text.trim() }))
    .filter((t) => t.text.length > 0)
    .slice(-maxTurns);
  if (cleaned.length === 0) return "";
  return cleaned
    .map((t) => {
      const label = t.role === "user" ? "Utilisateur" : "Assistant";
      return `${label}: ${t.text.slice(0, 600)}`;
    })
    .join("\n");
}
