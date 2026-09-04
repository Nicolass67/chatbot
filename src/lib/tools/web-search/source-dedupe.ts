import type { SearchResult } from "../types";

/** Clé canonique pour dédupliquer URL / mirrors / tracking. */
export function canonicalizeUrl(raw: string): string {
  try {
    const u = new URL(raw.trim());
    u.hash = "";
    u.hostname = u.hostname.replace(/^www\./i, "").toLowerCase();
    // Retire les paramètres de tracking courants
    for (const key of [...u.searchParams.keys()]) {
      if (
        /^(utm_|fbclid|gclid|mc_|ref|source$)/i.test(key) ||
        key.toLowerCase() === "s"
      ) {
        u.searchParams.delete(key);
      }
    }
    let path = u.pathname.replace(/\/+$/, "") || "/";
    // Normalise légèrement les chemins index.*
    path = path.replace(/\/index\.(html?|php|aspx?)$/i, "");
    u.pathname = path || "/";
    return `${u.protocol}//${u.host}${u.pathname}${u.search}`;
  } catch {
    return raw.trim().toLowerCase().replace(/\/+$/, "");
  }
}

/** Fusionne en dédupliquant ; retourne le nombre de nouvelles sources ajoutées. */
export function mergeUniqueSources(
  target: SearchResult[],
  incoming: SearchResult[],
  options?: { maxTotal?: number }
): number {
  const seen = new Set(target.map((s) => canonicalizeUrl(s.url)));
  let added = 0;
  const maxTotal = options?.maxTotal;

  for (const s of incoming) {
    if (maxTotal !== undefined && target.length >= maxTotal) break;
    const key = canonicalizeUrl(s.url);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    target.push(s);
    added++;
  }
  return added;
}

/** Déduplique + plafonne une liste (ordre conservé). */
export function dedupeAndCapSources(
  results: SearchResult[],
  max: number
): SearchResult[] {
  const out: SearchResult[] = [];
  mergeUniqueSources(out, results, { maxTotal: max });
  return out;
}
