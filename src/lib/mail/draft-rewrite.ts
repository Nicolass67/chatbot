/**
 * Réécriture de brouillon — même contrat que MailDraftRewriteWorkflow (iOS).
 * L’instruction utilisateur a priorité sur langue / ton / writing-prefs.
 */

export const MAIL_DRAFT_REWRITE_SYSTEM = `Tu réécris UNIQUEMENT le corps d’un e-mail existant.

PRIORITÉ 1 — USER INSTRUCTION (obligatoire) :
La consigne utilisateur a priorité sur la langue, le ton et le style du brouillon actuel.
Si elle demande une autre langue, le résultat DOIT être entièrement dans cette langue (pas un mélange, pas une traduction partielle).
Si elle demande un autre ton (moins formel, plus chaleureux, plus direct, plus court, plus professionnel…), applique un changement réel — pas une reformulation cosmétique.

PRIORITÉ 2 — FAITS :
Conserve noms, destinataires cités, dates, horaires, montants, références, demandes, liens, sauf si l’instruction demande explicitement de les modifier.
N’invente pas d’accords, de disponibilités, de pièces jointes ni de faits.

Règles de sortie :
- Sortie = le nouveau corps du mail, rien d’autre.
- Pas d’explication, pas de titre, pas de « voici une version », pas de markdown fence.
- N’ajoute PAS de signature (Cordialement, Best regards, nom) : l’application la pose.
- Ne change pas destinataires ni objet (gérés ailleurs).
- Le brouillon actuel est la seule source ; n’applique pas d’anciennes consignes absentes de USER INSTRUCTION.
- Le résultat DOIT être clairement différent du brouillon actuel (ton, longueur, formulation ou langue selon la consigne).
`;

export const MAIL_COMPOSE_DRAFT_SYSTEM = `Tu rédiges le corps d’un NOUVEL e-mail (pas une réponse de chatbot, pas un conseil).
Suit l’instruction utilisateur : langue, ton, contenu, destinataire implicite.
N’invente pas d’accords, de dates, de montants ni de pièces jointes. Si une info manque, mets [à préciser].
Sortie = le corps du mail uniquement. Pas de « Voici le mail », pas de markdown fence.
N’ajoute PAS de signature : l’application la pose.
N’écris JAMAIS que le message a été envoyé.
`;

export function buildRewriteUserPrompt(input: {
  instruction: string;
  body: string;
  to?: string;
  subject?: string;
  forceVisibleChange?: boolean;
}): string {
  const consigne = input.instruction.trim() || "Plus clair et naturel.";
  const to = (input.to ?? "").trim() || "(inchangé)";
  const subject = (input.subject ?? "").trim() || "(inchangé)";
  const force = input.forceVisibleChange
    ? `

CRITICAL:
Your previous rewrite was too similar to CURRENT DRAFT.
Apply USER INSTRUCTION aggressively so the new body is CLEARLY different
(tone, length, wording, or language as requested). Do not return the same text.`
    : "";
  return `USER INSTRUCTION:
${consigne}

CURRENT DRAFT:
${input.body}

MAIL CONTEXT:
Destinataire (ne pas modifier): ${to}
Objet (ne pas modifier): ${subject}

TASK:
Rewrite CURRENT DRAFT according to USER INSTRUCTION only.
The current draft is the source of truth. Do not re-apply older instructions.
Output MUST reflect the instruction with a visible change.${force}`;
}

export function normalizeRewriteForCompare(text: string): string {
  return text
    .toLowerCase()
    .split(/\s+/)
    .filter(Boolean)
    .join(" ");
}

export function isNearlyIdenticalRewrite(a: string, b: string): boolean {
  const na = normalizeRewriteForCompare(a);
  const nb = normalizeRewriteForCompare(b);
  if (!na || !nb) return false;
  if (na === nb) return true;
  const [shorter, longer] = na.length <= nb.length ? [na, nb] : [nb, na];
  if (shorter.length >= 40 && longer.includes(shorter) && longer.length - shorter.length < 48) {
    return true;
  }
  return false;
}

export function buildComposeUserPrompt(input: {
  instruction: string;
  recipientHint?: string;
}): string {
  const hint = (input.recipientHint ?? "").trim() || "(à remplir)";
  return `USER INSTRUCTION:
${input.instruction.trim()}

Destinataire hint: ${hint}

TASK:
Write the email body only.`;
}

export function stripRewriteMeta(raw: string): string {
  let t = raw.trim();
  if (t.startsWith("```")) {
    t = t.replace(/^```[a-zA-Z]*\n?/, "");
    const end = t.lastIndexOf("```");
    if (end >= 0) t = t.slice(0, end);
  }
  const prefixes = [
    "voici une version",
    "voici le mail",
    "voici le nouveau",
    "version moins formelle",
    "version plus formelle",
    "j’ai réécrit",
    "j'ai réécrit",
    "rewritten email:",
  ];
  const lower = t.toLowerCase();
  for (const p of prefixes) {
    if (lower.startsWith(p)) {
      const nl = t.indexOf("\n");
      if (nl >= 0) t = t.slice(nl + 1).trim();
      break;
    }
  }
  return t.trim();
}
