/**
 * Continuité conversationnelle : follow-ups anaphoriques + ancrage des requêtes web.
 *
 * Règle produit : dès qu’il existe un historique utilisateur, un tour ambigu
 * (top N, « modèles », « maintenant », etc.) DOIT rester ancré sur le sujet
 * précédent — jamais repartir sur un thème générique (ex. LLM).
 */

const ANAPHORA_RE =
  /\b(ça|cela|celui|celle|ceux|celles|il|elle|lui|eux|elles|leur|leurs|en|y|pareil|idem|modèles?|models?|marques?|options?|ceux[- ]là|celles[- ]là|celui[- ]là|celle[- ]là|maintenant|aussi|également|lesquels|lesquelles|lequel|laquelle|combien|dessus|ci[- ]dessus|précédent|précédente|mentionné|mentionnée|évoqué|évoquée|pareils?|ci[- ]avant|qu['’]il|qu['’]elle)\b/i;

/**
 * Affinage de contrainte (prix / budget / taille…) sans nouveau sujet métier.
 * Ex. « entre 200 et 300 € », « plutôt silencieux », « sous 150 euros ».
 */
const CONSTRAINT_REFINEMENT_RE =
  /\b(entre\s+\d+|\d+\s*(€|euros?|eur)\b|sous\s+\d+|moins\s+de\s+\d+|budget|prix|co[uû]te|co[uû]ter|co[uû]tent|environ\s+\d+|fourchette|gamme\s+de\s+prix)\b/i;

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
    // contraintes / mots fonction (ne définissent pas un domaine)
    "entre",
    "budget",
    "prix",
    "coute",
    "couter",
    "coutent",
    "coute",
    "aimerai",
    "aimerais",
    "voudrais",
    "veux",
    "possible",
    "euros",
    "euro",
    "fourchette",
    "environ",
    "moins",
    "sous",
    "plutot",
    "plutôt",
    "cherche",
    "chercher",
    "disponible",
    "disponibles",
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

  // Affinage prix/contrainte sans nouveau sujet métier = suite (ex. « entre 200 et 300 € »).
  if (isConstraintOnlyRefinement(t)) return true;

  return false;
}

/** True si le message affine budget/contrainte sans introduire de nouveau domaine. */
export function isConstraintOnlyRefinement(text: string): boolean {
  const t = text.trim();
  if (!t) return false;
  if (!CONSTRAINT_REFINEMENT_RE.test(t)) return false;
  return !hasConcreteDomain(t);
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
    .filter((t) => {
      if (t.length >= 4) return true;
      // Codes courts avec chiffre — utiles pour ancrer un follow-up.
      return t.length >= 3 && /\d/.test(t);
    });
}

/**
 * Entités produit-like domaine-agnostiques (lettres + chiffres).
 * Aucune whitelist de marques / catégories métier.
 */
export function extractTopicEntityHints(text: string, max = 6): string[] {
  const raw = text.slice(0, 8_000);
  const found: string[] = [];

  // Ex. « Marque 123 », « Code-45B », éventuellement un suffixe court (« Pro », « Ti »…).
  const spaced =
    raw.match(
      /\b[A-Za-z][A-Za-z0-9]{1,24}(?:[\s\-][A-Za-z0-9]{1,16}){0,3}\s+\d{2,5}[A-Za-z0-9]{0,10}(?:\s+[A-Za-z][A-Za-z0-9]{0,11})?\b/gi
    ) ?? [];
  const compact =
    raw.match(/\b[A-Za-z]{2,14}[\-]?\d{2,5}[A-Za-z0-9]{0,10}\b/g) ?? [];

  for (const m of [...spaced, ...compact]) {
    const t = m.replace(/\s+/g, " ").trim();
    if (t.length < 4) continue;
    if (/^\d{4}$/.test(t)) continue;
    if (/^(janvier|février|fevrier|mars|avril|mai|juin|juillet|août|aout|septembre|octobre|novembre|décembre|decembre)$/i.test(t)) {
      continue;
    }
    found.push(t);
  }

  const seen = new Set<string>();
  const out: string[] = [];
  // Préférer les formes longues (« Foo 12 Pro » avant « 12 »).
  found.sort((a, b) => b.length - a.length);
  for (const item of found) {
    const key = item.toLowerCase();
    if (seen.has(key)) continue;
    if (out.some((o) => o.toLowerCase().includes(key) && o.length > item.length)) {
      continue;
    }
    seen.add(key);
    out.push(item);
    if (out.length >= max) break;
  }
  return out;
}

/** True si la requête web est trop vague pour se passer de l’historique. */
export function isAmbiguousSearchQuery(query: string): boolean {
  const t = query.trim();
  if (!t) return false;
  if (AMBIGUOUS_SUBJECT_RE.test(t) && !hasConcreteDomain(t)) return true;
  if (RANKING_FOLLOW_UP_RE.test(t) && !hasConcreteDomain(t)) return true;
  if (isConstraintOnlyRefinement(t)) return true;
  if (ANAPHORA_RE.test(t) && !hasConcreteDomain(t)) return true;
  return false;
}

function uniqPreserveOrder(items: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const item of items) {
    const key = item.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(item);
  }
  return out;
}

/** Ancre une requête web avec le contexte récent si le tour est un follow-up. */
export function groundSearchQueryWithContext(params: {
  query: string;
  recentUserMessages: string[];
  /** Tours assistant récents — porte les entités déjà citées (ex. 3 modèles). */
  recentAssistantExcerpts?: string[];
  force?: boolean;
}): string {
  const query = params.query.trim();
  if (!query) return query;
  const priors = params.recentUserMessages.map((m) => m.trim()).filter(Boolean);
  const assistantExcerpts = (params.recentAssistantExcerpts ?? [])
    .map((m) => m.trim())
    .filter(Boolean);
  if (priors.length === 0 && assistantExcerpts.length === 0) return query;

  const hasHistory = priors.length > 0 || assistantExcerpts.length > 0;
  const shouldGround =
    params.force === true ||
    isFollowUpTurn(query, hasHistory) ||
    isAmbiguousSearchQuery(query);
  if (!shouldGround) return query;

  const queryLower = query.toLowerCase();

  // 1) Entités de la dernière réponse assistant (priorité sur l’anaphore vague).
  const assistantEntities = uniqPreserveOrder(
    assistantExcerpts.flatMap((t) => extractTopicEntityHints(t, 8))
  ).slice(0, 6);
  const missingAssistant = assistantEntities.filter(
    (e) => !queryLower.includes(e.toLowerCase())
  );

  if (missingAssistant.length > 0) {
    // Sujet ambigu (« modèles ») + entités résolues → réécriture intent + entités.
    if (AMBIGUOUS_SUBJECT_RE.test(query) || missingAssistant.length >= 2) {
      const priceIntent = /\b(prix|tarif|co[uû]te|co[uû]ter|budget|combien)\b/i.test(
        query
      );
      if (priceIntent) {
        return `prix ${missingAssistant.join(" ")}`
          .replace(/\s+/g, " ")
          .trim()
          .slice(0, 220);
      }
      return `${query} — sujets: ${missingAssistant.join(", ")}`
        .replace(/\s+/g, " ")
        .trim()
        .slice(0, 220);
    }
    return `${query} — sujets: ${missingAssistant.join(", ")}`
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, 220);
  }

  // 2) Entités / tokens des messages user antérieurs.
  const userEntities = uniqPreserveOrder(
    priors.flatMap((t) => extractTopicEntityHints(t, 4))
  ).slice(0, 4);
  const missingUserEntities = userEntities.filter(
    (e) => !queryLower.includes(e.toLowerCase())
  );
  if (missingUserEntities.length > 0 && AMBIGUOUS_SUBJECT_RE.test(query)) {
    return `${query} — sujets: ${missingUserEntities.join(", ")}`
      .replace(/\s+/g, " ")
      .trim()
      .slice(0, 220);
  }

  if (priors.length === 0) return query;

  const priorText = priors.slice(-2).join(" ");
  const priorTokens = significantTokens(priorText).filter(
    (t) => !AMBIGUOUS_TOKEN_SET.has(t)
  );

  // Ne plus no-op silencieux : même sans token « long », ancrer sur le message prior.
  if (priorTokens.length === 0) {
    const anchor = priors[priors.length - 1]!.slice(0, 180);
    return `${query} — contexte conversation: ${anchor}`
      .replace(/\s+/g, " ")
      .trim();
  }

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
