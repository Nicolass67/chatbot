/**
 * Continuité conversationnelle : follow-ups anaphoriques + ancrage des requêtes web.
 *
 * Règle produit : dès qu’il existe un historique utilisateur, un tour ambigu
 * (top N, « modèles », « maintenant », etc.) DOIT rester ancré sur le sujet
 * précédent — jamais repartir sur un thème générique (ex. LLM).
 */

const ANAPHORA_RE =
  /\b(ça|cela|celui|celle|ceux|celles|leur|leurs|en|y|pareil|idem|modèles?|models?|marques?|options?|ceux[- ]là|celles[- ]là|celui[- ]là|celle[- ]là|maintenant|aussi|également|lesquels|lesquelles|lequel|laquelle|combien|dessus|ci[- ]dessus|précédent|précédente|mentionné|mentionnée|évoqué|évoquée|pareils?|ci[- ]avant)\b/i;

const IMPERATIVE_FOLLOW_UP_RE =
  /^(oui\s+)?(donne|dis|montre|liste|cite|compare|détaille|detaille|explique|trouve|propose|indique|sélectionne|selectionne|reprends?|continue|fais|fait|recherche|recherches|cherche|cherches)\b/i;

const EXPLICIT_FOLLOW_UP_RE =
  /^(et (lui|elle|eux|ça|cela|le|la|les|mon|ma|mes|celui|celle|ceux)\b|fais pareil|pareil|idem|envoie[- ]?le|vérifie(\s|$)|le deuxième|la deuxième|et pour moi)\b/i;

/** Top N / classement sans sujet métier explicite → presque toujours un follow-up. */
const RANKING_FOLLOW_UP_RE =
  /\b(top\s*\d+|classement|comparatif|meilleur(?:e|es)?|les\s+\d+\s+meilleurs?)\b/i;

/**
 * Noms génériques qui ne définissent PAS un nouveau sujet à eux seuls.
 * « modèles » / « models » seuls → on ancre sur l’historique.
 */
const AMBIGUOUS_SUBJECT_RE =
  /\b(modèles?|models?|marques?|versions?|options?|produits?|références?|articles?)\b/i;

const AMBIGUOUS_TOKEN_SET = new Set(
  [
    // sujets génériques
    "modele",
    "modeles",
    "model",
    "models",
    "marque",
    "marques",
    "version",
    "versions",
    "option",
    "options",
    "produit",
    "produits",
    "reference",
    "references",
    "article",
    "articles",
    // classements / intent
    "top",
    "classement",
    "comparatif",
    "meilleur",
    "meilleurs",
    "meilleure",
    "meilleures",
    // verbes / mots fonction (ne définissent pas un domaine)
    "peux",
    "peut",
    "pouvez",
    "donne",
    "donner",
    "donnees",
    "montre",
    "montrer",
    "liste",
    "lister",
    "fais",
    "fait",
    "faire",
    "besoin",
    "recherche",
    "rechercher",
    "recherches",
    "cherche",
    "cherches",
    "internet",
    "maintenant",
    "aussi",
    "egalement",
    "clairement",
    "svp",
    "please",
    "merci",
    "bonjour",
    "salut",
  ].join(" ").split(/\s+/)
);

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

  // Court = follow-up par défaut dès qu’on a un historique.
  if (hasPriorUserMessages && words.length <= 6) return true;
  if (words.length <= 4) return true;

  if (words.length <= 10 && EXPLICIT_FOLLOW_UP_RE.test(t)) return true;
  if (!hasPriorUserMessages) return false;

  // Anaphore / impératif : plus de cliff artificiel à 14 mots.
  // Les follow-ups réels font souvent 15–25 mots.
  if (ANAPHORA_RE.test(t)) return true;
  if (words.length <= 16 && IMPERATIVE_FOLLOW_UP_RE.test(t)) return true;

  // « top 10 des models » / classement sans nouveau domaine = suite.
  if (RANKING_FOLLOW_UP_RE.test(t) && AMBIGUOUS_SUBJECT_RE.test(t)) return true;
  if (RANKING_FOLLOW_UP_RE.test(t) && !hasConcreteDomain(t)) return true;

  return false;
}

function hasConcreteDomain(text: string): boolean {
  return significantTokens(text).some(
    (tok) => !AMBIGUOUS_TOKEN_SET.has(tok) && tok.length >= 5
  );
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

/** True si la requête web est trop vague pour se passer de l’historique. */
export function isAmbiguousSearchQuery(query: string): boolean {
  const t = query.trim();
  if (!t) return false;
  if (AMBIGUOUS_SUBJECT_RE.test(t) && !hasConcreteDomain(t)) return true;
  if (RANKING_FOLLOW_UP_RE.test(t) && !hasConcreteDomain(t)) return true;
  return false;
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

  const shouldGround =
    params.force === true ||
    isFollowUpTurn(query, true) ||
    isAmbiguousSearchQuery(query);
  if (!shouldGround) return query;

  const priorText = priors.slice(-2).join(" ");
  const priorTokens = significantTokens(priorText);
  if (priorTokens.length === 0) return query;

  const queryLower = query.toLowerCase();
  const missing = priorTokens
    .filter((t) => !queryLower.includes(t))
    .slice(0, 6);
  if (missing.length === 0) return query;

  const anchor = priors[priors.length - 1]!.slice(0, 180);
  return `${query} — contexte conversation: ${anchor}`
    .replace(/\s+/g, " ")
    .trim();
}

export function formatAgentConversationHistory(
  turns: Array<{ role: "user" | "assistant"; text: string }>,
  maxTurns = 8
): string {
  const cleaned = turns
    .map((t) => ({ role: t.role, text: t.text.trim() }))
    .filter((t) => t.text.length > 0)
    .slice(-maxTurns);
  if (cleaned.length === 0) return "";
  return cleaned
    .map((t) => {
      const label = t.role === "user" ? "Utilisateur" : "Assistant";
      return `${label}: ${t.text.slice(0, 800)}`;
    })
    .join("\n");
}
