import type {
  EvidencePacket,
  SourceAnalysisResult,
  WebEvidenceItem,
} from "./types";

/** Cible ~150–300 tokens ≈ 600–1200 chars utiles. */
export const EVIDENCE_PACKET_MAX_CHARS = 1200;

export function buildEvidencePacket(params: {
  analysis: SourceAnalysisResult;
  extractionStatus?: EvidencePacket["extractionStatus"];
  caveats?: string[];
  contradictions?: string[];
  relevantFacts?: string[];
  importantValues?: string[];
}): EvidencePacket {
  const items = params.analysis.extracted;
  const extractionStatus =
    params.extractionStatus ??
    params.analysis.extractionStatus ??
    (items.length > 0 ? "ok" : "empty");

  const relevantFacts =
    params.relevantFacts && params.relevantFacts.length > 0
      ? params.relevantFacts
      : items.map((i) => i.claim).filter(Boolean);

  const importantValues =
    params.importantValues && params.importantValues.length > 0
      ? params.importantValues
      : items
          .map((i) => i.value)
          .filter((v): v is string => Boolean(v && v.trim()));

  const caveats = params.caveats ?? [];
  const contradictions = params.contradictions ?? [];

  const compactEvidence = formatCompactEvidence({
    sourceId: params.analysis.sourceId,
    url: params.analysis.url,
    title: params.analysis.title,
    relevantFacts,
    importantValues,
    caveats,
    contradictions,
    items,
  });

  return {
    sourceId: params.analysis.sourceId,
    url: params.analysis.url,
    title: params.analysis.title,
    retrievedAt: items[0]?.retrievedAt ?? new Date().toISOString(),
    publicationDate: items[0]?.publicationDate,
    relevantFacts: relevantFacts.slice(0, 12),
    importantValues: importantValues.slice(0, 12),
    caveats: caveats.slice(0, 6),
    contradictions: contradictions.slice(0, 6),
    compactEvidence,
    extractionStatus,
    items,
  };
}

export function formatCompactEvidence(params: {
  sourceId: string;
  url: string;
  title: string;
  relevantFacts: string[];
  importantValues: string[];
  caveats: string[];
  contradictions: string[];
  items: WebEvidenceItem[];
}): string {
  const lines: string[] = [];
  lines.push(`SOURCE: ${params.title || params.url}`);
  lines.push(`url: ${params.url}`);
  lines.push(`sourceId: ${params.sourceId}`);

  for (const v of params.importantValues.slice(0, 8)) lines.push(`- ${v}`);

  const facts = params.relevantFacts
    .filter(
      (f) =>
        !params.importantValues.some((v) => f.includes(v) || v.includes(f))
    )
    .slice(0, 8);
  for (const f of facts) lines.push(`- ${f}`);

  for (const c of params.caveats.slice(0, 3)) lines.push(`- caveat: ${c}`);
  for (const c of params.contradictions.slice(0, 3)) {
    lines.push(`- contradiction: ${c}`);
  }

  if (params.importantValues.length === 0 && facts.length === 0) {
    for (const it of params.items.slice(0, 6)) {
      lines.push(
        (it.value ? `- ${it.claim} → ${it.value}` : `- ${it.claim}`).slice(
          0,
          180
        )
      );
    }
  }

  let out = lines.join("\n");
  if (out.length > EVIDENCE_PACKET_MAX_CHARS) {
    out = `${out.slice(0, EVIDENCE_PACKET_MAX_CHARS - 1)}…`;
  }
  return out;
}

export function formatEvidencePacketsBlock(
  packets: EvidencePacket[],
  options?: { maxPackets?: number; maxChars?: number }
): string {
  const maxPackets = options?.maxPackets ?? 12;
  const maxChars = options?.maxChars ?? 10_000;
  const usable = packets.filter(
    (p) =>
      p.extractionStatus === "ok" ||
      p.relevantFacts.length > 0 ||
      p.items.length > 0
  );

  const lines: string[] = [];
  lines.push("<web_evidence>");
  lines.push(
    "Preuves condensées (extraction orientée question, PAS résumé de page). S'en servir pour répondre à l'utilisateur — ne pas réciter les sources. Contradictions: nuance courte. Citer url/sourceId. Ne pas inventer. Info absente: le dire sans absence absolue mondiale."
  );

  let used = lines.join("\n").length;
  let count = 0;
  for (const p of usable.slice(0, maxPackets)) {
    const block = [
      `<packet sourceId="${p.sourceId}" status="${p.extractionStatus}">`,
      p.compactEvidence,
      `</packet>`,
    ].join("\n");
    if (used + block.length + 1 > maxChars) break;
    lines.push(block);
    used += block.length + 1;
    count += 1;
  }
  lines.push(`packets_included: ${count}`);
  lines.push("</web_evidence>");
  return lines.join("\n");
}
