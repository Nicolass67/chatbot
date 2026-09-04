import { getEmailProvider } from "@/lib/integrations/email/factory";
import { getOAuthAccount } from "@/lib/integrations/oauth";
import type { NormalizedEmailMessage } from "@/lib/integrations/email/types";

export interface RecipientCandidate {
  email: string;
  displayName?: string;
  score: number;
  source: "self" | "sent" | "inbox" | "thread";
}

export type RecipientResolution =
  | { status: "self"; email: string }
  | { status: "resolved"; email: string; displayName?: string; source: string }
  | { status: "ambiguous"; query: string; candidates: RecipientCandidate[] }
  | { status: "unresolved"; query: string };

const SELF_RE =
  /\b(moi[- ]?même|à moi|a moi|mon adresse|à mon adresse|myself|to myself|me\-même)\b/i;

/** Détecte si le message demande d'écrire à soi-même. */
export function messageImpliesSelfRecipient(message: string): boolean {
  return SELF_RE.test(message.trim());
}

/**
 * Extrait un nom de destinataire probable (sans inventer d'email).
 * Ex. « Écris un mail à Maxime Plançon pour… » → « Maxime Plançon »
 */
export function extractRecipientNameHint(message: string): string | null {
  if (messageImpliesSelfRecipient(message)) return null;
  const patterns = [
    /\b(?:à|a|pour|au|à destination de)\s+([A-ZÀ-Ÿ][\wÀ-ÿ'’-]+(?:\s+[A-ZÀ-Ÿ][\wÀ-ÿ'’-]+){0,3})\b/,
    /\b(?:écris|ecris|envoie|envoyer|rédige|redige|mail|email|courriel)\s+(?:un\s+)?(?:mail|email|message)?\s*(?:à|a)\s+([A-ZÀ-Ÿ][\wÀ-ÿ'’-]+(?:\s+[A-ZÀ-Ÿ][\wÀ-ÿ'’-]+){0,3})\b/i,
    /\b(?:réponds|reponds|répondre|repondre)\s+(?:à|a)\s+([A-ZÀ-Ÿ][\wÀ-ÿ'’-]+(?:\s+[A-ZÀ-Ÿ][\wÀ-ÿ'’-]+){0,3})\b/i,
  ];
  const stopWords = new Set([
    "pour",
    "afin",
    "concernant",
    "au",
    "sujet",
    "demain",
    "aujourd",
    "avec",
    "sans",
    "et",
    "de",
    "du",
    "des",
  ]);
  for (const re of patterns) {
    const m = message.match(re);
    if (m?.[1]) {
      const parts = m[1]
        .trim()
        .split(/\s+/)
        .filter((p) => !stopWords.has(p.toLowerCase()));
      const name = parts.join(" ").trim();
      if (name.length < 2) continue;
      if (/^(le|la|les|un|une|des|ce|cet|cette)$/i.test(name)) continue;
      if (/@/.test(name)) continue;
      return name;
    }
  }
  return null;
}

function normalizeName(s: string): string {
  return s
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\w\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function nameTokens(s: string): string[] {
  return normalizeName(s)
    .split(" ")
    .filter((t) => t.length > 1);
}

function scoreAddressAgainstQuery(
  query: string,
  email: string,
  displayName?: string
): number {
  const qTokens = nameTokens(query);
  if (qTokens.length === 0) return 0;
  const hay = normalizeName(`${displayName ?? ""} ${email.split("@")[0] ?? ""}`);
  if (!hay) return 0;
  let hits = 0;
  for (const t of qTokens) {
    if (hay.includes(t)) hits++;
  }
  const ratio = hits / qTokens.length;
  if (ratio < 0.5) return 0;
  // Bonus si tous les tokens matchent
  return ratio * 10 + (displayName ? 2 : 0) + (hits === qTokens.length ? 3 : 0);
}

function collectFromMessages(
  messages: NormalizedEmailMessage[],
  query: string,
  source: RecipientCandidate["source"]
): Map<string, RecipientCandidate> {
  const map = new Map<string, RecipientCandidate>();
  const consider = (email: string, displayName?: string) => {
    const e = email.trim().toLowerCase();
    if (!e || !e.includes("@")) return;
    const score = scoreAddressAgainstQuery(query, e, displayName);
    if (score <= 0) return;
    const prev = map.get(e);
    if (!prev || score > prev.score) {
      map.set(e, { email: e, displayName, score, source });
    }
  };

  for (const m of messages) {
    consider(m.from.email, m.from.name);
    for (const a of m.to) consider(a.email, a.name);
    for (const a of m.cc) consider(a.email, a.name);
  }
  return map;
}

async function resolveAccountEmail(
  userId: string,
  hint?: string | null
): Promise<string | null> {
  const fromHint = hint?.trim().toLowerCase();
  if (fromHint && fromHint.includes("@")) return fromHint;
  const account = await getOAuthAccount(userId, "gmail");
  const email = account?.accountEmail?.trim().toLowerCase();
  return email && email.includes("@") ? email : null;
}

/**
 * Résolution réelle des destinataires — jamais d'invention d'adresse.
 */
export async function resolveEmailRecipient(input: {
  userId: string;
  message: string;
  accountEmail?: string | null;
  explicitEmail?: string | null;
  toSelfHint?: boolean;
}): Promise<RecipientResolution> {
  const accountEmail = await resolveAccountEmail(
    input.userId,
    input.accountEmail
  );

  if (input.toSelfHint || messageImpliesSelfRecipient(input.message)) {
    if (accountEmail) {
      return { status: "self", email: accountEmail };
    }
    return { status: "unresolved", query: "moi-même" };
  }

  const explicit = input.explicitEmail?.trim().toLowerCase();
  if (explicit && explicit.includes("@")) {
    return {
      status: "resolved",
      email: explicit,
      source: "explicit",
    };
  }

  const nameQuery = extractRecipientNameHint(input.message);
  if (!nameQuery) {
    return { status: "unresolved", query: "" };
  }

  try {
    const provider = await getEmailProvider(input.userId);
    const quoted = `"${nameQuery.replace(/"/g, "")}"`;
    const [sent, inbox] = await Promise.all([
      provider.search({
        query: `in:sent ${quoted}`,
        maxResults: 25,
      }),
      provider.search({
        query: `{from:${quoted} to:${quoted}}`,
        maxResults: 25,
      }),
    ]);

    const merged = new Map<string, RecipientCandidate>();
    for (const [k, v] of collectFromMessages(sent, nameQuery, "sent")) {
      merged.set(k, v);
    }
    for (const [k, v] of collectFromMessages(inbox, nameQuery, "inbox")) {
      const prev = merged.get(k);
      if (!prev || v.score > prev.score) merged.set(k, v);
    }

    // Ne jamais proposer l'adresse du compte comme contact nommé
    if (accountEmail) merged.delete(accountEmail);

    const candidates = [...merged.values()].sort((a, b) => b.score - a.score);
    if (candidates.length === 0) {
      return { status: "unresolved", query: nameQuery };
    }
    if (
      candidates.length === 1 ||
      (candidates[0].score >= 12 &&
        candidates[0].score - (candidates[1]?.score ?? 0) >= 4)
    ) {
      return {
        status: "resolved",
        email: candidates[0].email,
        displayName: candidates[0].displayName,
        source: candidates[0].source,
      };
    }
    return {
      status: "ambiguous",
      query: nameQuery,
      candidates: candidates.slice(0, 5),
    };
  } catch {
    return { status: "unresolved", query: nameQuery };
  }
}
