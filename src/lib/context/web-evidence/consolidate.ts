import type {
  ConsolidatedEvidenceGroup,
  EvidenceAgreement,
  WebEvidenceItem,
} from "./types";

export type ParsedEvidenceValue = {
  raw: string;
  number?: number;
  unit?: string;
  currency?: string;
  vendor?: string;
  date?: string;
};

/** Fusionne sans écraser les contradictions — divergence contextualisée (V4). */
export function consolidateEvidence(
  items: WebEvidenceItem[]
): ConsolidatedEvidenceGroup[] {
  const groups = new Map<string, WebEvidenceItem[]>();

  for (const item of items) {
    const key = groupKey(item);
    const list = groups.get(key) ?? [];
    list.push(item);
    groups.set(key, list);
  }

  const out: ConsolidatedEvidenceGroup[] = [];
  for (const [key, groupItems] of groups) {
    const values = unique(
      groupItems.map((i) => (i.value ?? "").trim()).filter(Boolean)
    );
    out.push({
      key,
      claim: pickClaim(groupItems),
      items: groupItems,
      agreement: classifyAgreement(groupItems, values),
      values,
    });
  }

  out.sort((a, b) => {
    const rank = (g: ConsolidatedEvidenceGroup) =>
      g.agreement === "diverge" ? 0 : g.agreement === "agree" ? 1 : 2;
    return rank(a) - rank(b) || b.items.length - a.items.length;
  });

  return out;
}

export function parseEvidenceValue(raw: string): ParsedEvidenceValue {
  const text = raw.trim();
  const numMatch = text.match(/(\d+(?:[.,]\d+)?)/);
  const number = numMatch
    ? parseFloat(numMatch[1]!.replace(",", "."))
    : undefined;
  const currencyMatch = text.match(/(€|eur|euros?|\$|usd|dollars?)/i);
  const unitMatch = text.match(
    /\b(w|kw|mhz|ghz|go|mo|gb|mb|fps|ms|db|m³|m3|%|kg|g)\b/i
  );
  const dateMatch = text.match(
    /\b(20\d{2}[-/]\d{1,2}[-/]\d{1,2}|20\d{2}|\d{1,2}[/-]\d{1,2}[/-]20\d{2})\b/
  );
  const vendorMatch = text.match(
    /\b(?:chez|via|sur|vendor|seller|vendeur)\s+([A-Za-z0-9][\w.-]{1,40})/i
  );
  return {
    raw: text,
    number: Number.isFinite(number) ? number : undefined,
    unit: unitMatch?.[1]?.toLowerCase(),
    currency: currencyMatch?.[1]?.toLowerCase(),
    vendor: vendorMatch?.[1],
    date: dateMatch?.[1],
  };
}

function groupKey(item: WebEvidenceItem): string {
  const stem = normalize(item.claim)
    .replace(/\d+(?:[.,]\d+)?/g, "#")
    .replace(
      /\b(vaut|coute|coute|a|est|liste|euros?|eur|usd|dollars?|prix|price|ttc|ht|chez|sur)\b/g,
      " "
    )
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 48);
  return stem || item.id;
}

function classifyAgreement(
  items: WebEvidenceItem[],
  values: string[]
): EvidenceAgreement {
  if (items.length === 1) return "single";
  if (values.length <= 1) {
    const urls = unique(items.map((i) => i.url));
    return urls.length === 1 ? "duplicate" : "agree";
  }

  const parsed = values.map(parseEvidenceValue);
  const nums = parsed
    .map((p) => p.number)
    .filter((n): n is number => typeof n === "number" && Number.isFinite(n));

  if (nums.length >= 2) {
    const min = Math.min(...nums);
    const max = Math.max(...nums);
    const rel = min > 0 ? (max - min) / min : max - min;

    // Même ordre de grandeur (±5%) → agree
    if (rel <= 0.05) return "agree";

    // Divergence modérée avec vendeurs/dates différents → diverge (légitime, conservée)
    const vendors = unique(parsed.map((p) => p.vendor ?? "").filter(Boolean));
    const dates = unique(parsed.map((p) => p.date ?? "").filter(Boolean));
    if (rel <= 0.25 && (vendors.length > 1 || dates.length > 1)) {
      return "diverge";
    }

    // Écart fort → diverge (contradiction forte)
    return "diverge";
  }

  // Non numérique : diverge si strings distinctes
  return "diverge";
}

function pickClaim(items: WebEvidenceItem[]): string {
  const ranked = [...items].sort((a, b) => {
    const conf = (c: WebEvidenceItem["confidence"]) =>
      c === "high" ? 0 : c === "medium" ? 1 : 2;
    return conf(a.confidence) - conf(b.confidence);
  });
  return ranked[0]!.claim;
}

function normalize(s: string): string {
  return s
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function unique(arr: string[]): string[] {
  return [...new Set(arr)];
}
