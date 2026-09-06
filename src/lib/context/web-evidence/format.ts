import {
  formatWebSourcesForContext,
  type WebSourceRecord,
} from "@/lib/context/web-provenance";
import type {
  ConsolidatedEvidenceGroup,
  CoverageReport,
  WebEvidenceItem,
} from "./types";

export function formatEvidenceContextBlock(params: {
  evidence: WebEvidenceItem[];
  consolidated: ConsolidatedEvidenceGroup[];
  coverage: CoverageReport;
  maxEvidenceItems?: number;
}): string {
  const maxItems = params.maxEvidenceItems ?? 24;
  const lines: string[] = [];

  lines.push("<web_evidence>");
  lines.push(
    "INTERNE: utiliser les preuves pour conclure. Ne pas narrer la recherche."
  );
  lines.push(
    "Règles: preuves pour CONCLUSER (pas pour narrer la recherche). Prioriser sur texte brut. Citer url/sourceId. Ne pas inventer. Contradictions: fourchettes / nuance courte sauf si le verdict change."
  );
  lines.push(`coverage_sufficient: ${params.coverage.sufficient}`);
  lines.push(`coverage_reason: ${params.coverage.reason}`);

  if (params.coverage.missingNeedIds.length > 0) {
    lines.push(
      `missing_needs_internal: ${params.coverage.missingNeedIds.join(", ")}`
    );
    lines.push(
      "negative_claim_policy: manques = raisonnement interne. N'en parle à l'utilisateur que si critique pour répondre. Sinon: « non trouvé dans les preuves extraites » — jamais une absence absolue mondiale."
    );
  }

  const divergences = params.consolidated.filter(
    (g) => g.agreement === "diverge"
  );
  if (divergences.length > 0) {
    lines.push("<contradictions>");
    lines.push(
      "Utilisation: intégrer brièvement dans la réponse ; ne pas monopoliser avec un exposé source-par-source."
    );
    for (const g of divergences.slice(0, 8)) {
      lines.push(
        `- ${g.claim} | values=${JSON.stringify(g.values)} | sources=${g.items
          .map((i) => i.sourceId)
          .join(",")}`
      );
    }
    lines.push("</contradictions>");
  }

  lines.push("<evidence_items>");
  for (const item of params.evidence.slice(0, maxItems)) {
    lines.push(
      [
        `<evidence id="${item.id}" sourceId="${item.sourceId}" url="${item.url}" confidence="${item.confidence}"${item.needId ? ` needId="${item.needId}"` : ""}>`,
        `claim: ${item.claim}`,
        item.value ? `value: ${item.value}` : null,
        `title: ${item.title}`,
        `evidence: ${item.evidence}`,
        `retrievedAt: ${item.retrievedAt}`,
        `</evidence>`,
      ]
        .filter(Boolean)
        .join("\n")
    );
  }
  lines.push("</evidence_items>");
  lines.push("</web_evidence>");
  return lines.join("\n");
}

export function formatResidualSourcesBlock(
  sources: WebSourceRecord[],
  options?: { maxSources?: number; maxPageChars?: number }
): string {
  return formatWebSourcesForContext(sources, {
    maxSources: options?.maxSources ?? 2,
    maxPageChars: options?.maxPageChars ?? 350,
  });
}

export function buildFinalWebApplicationContext(params: {
  evidenceBlock: string;
  residualBlock: string;
  maxChars?: number;
}): string {
  const maxChars = params.maxChars ?? 10_000;
  const primary = params.evidenceBlock.trim();
  const residual = params.residualBlock.trim();
  if (!residual) return primary.slice(0, maxChars);
  if (!primary) return residual.slice(0, maxChars);

  const combined = `${primary}\n\n<secondary_web_sources>\n${residual}\n</secondary_web_sources>`;
  if (combined.length <= maxChars) return combined;

  const room = Math.max(0, maxChars - primary.length - 64);
  if (room < 200) return primary.slice(0, maxChars);
  return `${primary}\n\n<secondary_web_sources>\n${residual.slice(0, room)}…\n</secondary_web_sources>`;
}
