/**
 * Filet déterministe pour faits personnels évidents (ex: déménagement).
 * Complète le classifieur LLM local, trop strict sur les infos au futur.
 */

export type PersonalFactCandidate = {
  content: string;
  category: "other" | "preference" | "hardware" | "project" | "habit" | "communication";
  importance: number;
};

const MONTHS =
  "janvier|février|fevrier|mars|avril|mai|juin|juillet|août|aout|septembre|octobre|novembre|décembre|decembre";

function normalizeSpaces(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

function titleCity(raw: string): string {
  const t = raw.trim();
  if (!t) return t;
  return t.charAt(0).toUpperCase() + t.slice(1).toLowerCase();
}

/** Extrait des candidats mémoire depuis le message utilisateur (FR). */
export function extractPersonalFactCandidates(message: string): PersonalFactCandidate[] {
  const text = normalizeSpaces(message);
  if (text.length < 8) return [];

  const out: PersonalFactCandidate[] = [];
  const lower = text.toLowerCase();

  // Âge: "j'ai 26 ans" / "je suis âgé de 26 ans"
  const age =
    lower.match(/\bj['’]ai\s+(\d{1,2})\s*ans\b/) ||
    lower.match(/\b(?:âge|age)\s*(?:de|:)?\s*(\d{1,2})\b/) ||
    lower.match(/\bje\s+suis\s+(?:âgé|age)\s*(?:e)?\s*de\s+(\d{1,2})\b/);
  if (age?.[1]) {
    out.push({
      content: `L'utilisateur a ${age[1]} ans`,
      category: "other",
      importance: 0.9,
    });
  }

  // Prénom: "je m'appelle X"
  const name = text.match(/\bje\s+m['’]appelle\s+([A-ZÀ-Üa-zà-ü][\w'’\-]{1,30})/i);
  if (name?.[1] && !/^(un|une|le|la|les|des)$/i.test(name[1])) {
    out.push({
      content: `L'utilisateur s'appelle ${name[1]}`,
      category: "other",
      importance: 0.9,
    });
  }

  // Déménagement / installation / futur lieu de vie
  // Note: pas de \b avant "à" (accent) — en JS sans flag /u, \b échoue sur "à".
  const move =
    lower.match(
      /(?:déménag(?:e|er|ons|ez|ent)?|m['’]installe(?:r)?|vais\s+(?:habiter|vivre)|compte\s+(?:habiter|vivre)|prévois\s+de\s+(?:habiter|vivre))[\s\S]{0,80}?(?:à|au|en)\s+([a-zà-ü][\w'’\-]{1,40})/
    ) ||
    lower.match(
      /(?:déménagement|nouvelle\s+ville|nouvelle\s+adresse)[\s\S]{0,60}?(?:à|au|en)\s+([a-zà-ü][\w'’\-]{1,40})/
    );

  const date =
    lower.match(new RegExp(`\\ble\\s+(\\d{1,2})\\s+(${MONTHS})(?:\\s+(\\d{4}))?\\b`)) ||
    lower.match(new RegExp(`\\b(\\d{1,2})\\s+(${MONTHS})(?:\\s+(\\d{4}))?\\b`));

  if (move?.[1]) {
    const city = titleCity(move[1]);
    // Ignore faux positifs trop génériques
    if (!/^(la|le|les|un|une|des|mon|ma|mes|cette|ce)$/i.test(city)) {
      let content = `L'utilisateur déménage à ${city}`;
      if (date) {
        const day = date[1];
        const month = date[2];
        const year = date[3];
        content += year ? ` le ${day} ${month} ${year}` : ` le ${day} ${month}`;
      }
      out.push({ content, category: "other", importance: 0.9 });
    }
  } else if (
    /\b(?:déménag|m['’]install)/i.test(lower) &&
    date &&
    !move
  ) {
    // Date de déménagement sans ville clairement parsée
    const day = date[1];
    const month = date[2];
    const year = date[3];
    const when = year ? `${day} ${month} ${year}` : `${day} ${month}`;
    out.push({
      content: `L'utilisateur prévoit un déménagement le ${when}`,
      category: "other",
      importance: 0.85,
    });
  }

  // Déduplique sur contenu normalisé
  const seen = new Set<string>();
  return out.filter((item) => {
    const key = item.content.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return item.content.length >= 10;
  });
}

export function mergePersonalFacts<T extends { content: string }>(
  primary: T[],
  extras: PersonalFactCandidate[]
): Array<T | PersonalFactCandidate> {
  const seen = new Set(primary.map((m) => m.content.toLowerCase().slice(0, 40)));
  const merged: Array<T | PersonalFactCandidate> = [...primary];
  for (const extra of extras) {
    const key = extra.content.toLowerCase().slice(0, 40);
    const overlap = [...seen].some(
      (s) => s.includes(key.slice(0, 20)) || key.includes(s.slice(0, 20))
    );
    if (overlap) continue;
    seen.add(key);
    merged.push(extra);
  }
  return merged;
}
