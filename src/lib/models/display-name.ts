/**
 * Libellés d'affichage pour les IDs / noms de modèles LM Studio / GGUF.
 * Les noms complets restent disponibles via title / tooltip.
 */

const QUANT_RE =
  /(?:^|[-_\s.])((?:IQ|UQ|EXL2|FP|BF|Q)\d+[A-Z0-9_]*)(?=$|[-_\s.]|\.gguf$)/i;

function leafName(modelKey: string): string {
  const leaf = modelKey.split(/[/\\]/).pop() ?? modelKey;
  return leaf.replace(/\.gguf$/i, "").trim();
}

function shortenQuant(raw: string): string {
  const head = raw.match(/^(IQ\d+|UQ\d+|EXL2|FP\d+|BF\d+|Q\d+)/i);
  return (head?.[1] ?? raw).toUpperCase();
}

/** Nom lisible « complet » (sans chemin, séparateurs normalisés). */
export function formatModelFullName(modelKey: string | null | undefined): string {
  if (!modelKey?.trim()) return "";
  return leafName(modelKey)
    .replace(/[_]+/g, " ")
    .replace(/[-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * Version compacte pour pastilles / triggers étroits.
 * Ex. `Qwen3.8-27B-IQ4_XS_4BPW` → `Qwen3.8-27B · IQ4`
 */
export function formatModelCompactName(
  modelKey: string | null | undefined,
  maxChars = 26
): string {
  if (!modelKey?.trim()) return "";
  const leaf = leafName(modelKey);
  const full = formatModelFullName(leaf);

  const quantMatch = leaf.match(QUANT_RE);
  if (quantMatch?.[1] && quantMatch.index !== undefined && quantMatch.index > 0) {
    const quantShort = shortenQuant(quantMatch[1]);
    let base = leaf
      .slice(0, quantMatch.index)
      .replace(/[-_\s.]+$/g, "")
      .replace(/_+/g, "-");
    if (!base) base = full;
    const candidate = `${base} · ${quantShort}`;
    if (candidate.length <= maxChars) return candidate;
    return `${candidate.slice(0, Math.max(1, maxChars - 1)).trimEnd()}…`;
  }

  if (full.length <= maxChars) return full;
  if (maxChars <= 1) return "…";
  return `${full.slice(0, Math.max(1, maxChars - 1)).trimEnd()}…`;
}

export function shortModelName(
  modelKey: string | null | undefined
): string | null {
  if (!modelKey?.trim()) return null;
  return formatModelCompactName(modelKey);
}
