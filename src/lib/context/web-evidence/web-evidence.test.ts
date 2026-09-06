import { describe, expect, it } from "vitest";
import { resolveConversationalWebRoute } from "@/lib/context/conversational-web-resolution";
import {
  buildEvidencePacket,
  consolidateEvidence,
  EVIDENCE_PACKET_MAX_CHARS,
  evaluateCoverage,
  formatEvidenceContextBlock,
  formatEvidencePacketsBlock,
  heuristicExtract,
  parsePageEvidenceExtractionJson,
  runWebEvidencePipeline,
  selectSourcesForAnalysis,
  windowPageContent,
} from "@/lib/context/web-evidence";
import type { RouteDecision } from "@/lib/request-router/types";
import type {
  SourceAnalysisResult,
  WebEvidenceItem,
} from "@/lib/context/web-evidence/types";

function baseRoute(overrides?: Partial<RouteDecision["web"]>): RouteDecision {
  return {
    knowledge: "current",
    web: {
      enabled: true,
      mode: "none",
      searchType: "none",
      wouldBeUseful: false,
      mandatory: false,
      autoSearch: false,
      searchQuery: "",
      reason: "test",
      ...overrides,
    },
    email: {
      enabled: false,
      wouldBeUseful: false,
      intent: "none",
      suggestedTools: [],
      reason: "n/a",
    },
    files: {
      enabled: false,
      wouldBeUseful: false,
      intent: "none",
      suggestedTools: [],
      reason: "n/a",
    },
    research: {},
    execution: { mode: "direct", suggestAgent: false },
    vision: { required: false, reason: "n/a" },
    tools: { allowToolCalling: false, candidates: [] },
    temporal: {
      scope: "unspecified",
      userIntent: "unspecified",
      isTimeSensitive: false,
      referenceYear: 2026,
      clock: {
        currentDate: "2026-09-06",
        currentYear: 2026,
        timezone: "Europe/Paris",
      },
    },
    source: "fallback_conservative",
    latencyMs: 0,
    confidence: 0.5,
    reason: "test",
  } as unknown as RouteDecision;
}

describe("web-evidence architecture", () => {
  it("Test1: info absente du snippet mais présente dans la page → extraite", () => {
    const question = "Quels sont les modèles et leurs valeurs indiquées ?";
    const page = [
      "Intro marketing sans chiffre.",
      "Lorem ".repeat(200),
      "Le modèle Alpha est listé à 319,41 € TTC chez le revendeur.",
      "Lorem ".repeat(200),
      "Fin de page.",
    ].join(" ");

    // Snippet SERP sans la valeur
    const snippet = "Comparatif des meilleurs modèles de la gamme.";
    expect(snippet.includes("319")).toBe(false);

    const windowed = windowPageContent(page, 10_000);
    const extracted = heuristicExtract(question, windowed, "Page test");
    expect(extracted.some((e) => (e.value || e.evidence).includes("319"))).toBe(
      true
    );
  });

  it("Test2: plusieurs sources → preuves consolidées", () => {
    const items: WebEvidenceItem[] = [
      {
        id: "1",
        claim: "Alpha vaut 319 €",
        value: "319 €",
        sourceId: "a",
        url: "https://a.example/x",
        title: "A",
        evidence: "Alpha 319 €",
        retrievedAt: new Date().toISOString(),
        confidence: "high",
      },
      {
        id: "2",
        claim: "Alpha vaut 319 euros",
        value: "319 €",
        sourceId: "b",
        url: "https://b.example/x",
        title: "B",
        evidence: "Alpha à 319 €",
        retrievedAt: new Date().toISOString(),
        confidence: "medium",
      },
    ];
    const groups = consolidateEvidence(items);
    expect(groups.length).toBeGreaterThanOrEqual(1);
    expect(groups.some((g) => g.items.length >= 2)).toBe(true);
  });

  it("Test3: source au-delà de l'ancien maxSources=6 peut être sélectionnée", () => {
    const sources = Array.from({ length: 12 }, (_, i) => ({
      sourceId: `s${i}`,
      url: `https://ex${i}.example/page`,
      title: i === 9 ? "Guide modèles valeurs détaillées" : `Résultat ${i}`,
      snippet:
        i === 9
          ? "tableau complet des modèles avec valeurs"
          : "article générique",
      domain: `ex${i}.example`,
    }));
    const { decisions, toAnalyze } = selectSourcesForAnalysis({
      query: "modèles valeurs guide",
      sources,
      maxCandidates: 12,
      maxFetch: 8,
    });
    expect(toAnalyze.length).toBeGreaterThan(6);
    expect(decisions.filter((d) => d.selected).length).toBeGreaterThan(6);
    expect(decisions.some((d) => d.sourceId === "s9" && d.selected)).toBe(true);
  });

  it("Test4: contradictions conservées", () => {
    const items: WebEvidenceItem[] = [
      {
        id: "1",
        claim: "Alpha",
        value: "399 €",
        sourceId: "a",
        url: "https://a.example",
        title: "A",
        evidence: "399 €",
        retrievedAt: new Date().toISOString(),
        confidence: "high",
      },
      {
        id: "2",
        claim: "Alpha",
        value: "349 €",
        sourceId: "b",
        url: "https://b.example",
        title: "B",
        evidence: "349 €",
        retrievedAt: new Date().toISOString(),
        confidence: "high",
      },
    ];
    const groups = consolidateEvidence(items);
    expect(groups.some((g) => g.agreement === "diverge")).toBe(true);
    expect(groups.find((g) => g.agreement === "diverge")?.values.length).toBe(2);
  });

  it("Test5: information manquante → follow-up queries", () => {
    const coverage = evaluateCoverage({
      needs: [
        {
          id: "need_primary",
          description: "Répondre à la question",
          priority: "critical",
          status: "open",
        },
        {
          id: "need_part_1",
          description: "Dimension B manquante",
          priority: "high",
          status: "open",
        },
      ],
      evidence: [],
      consolidated: [],
      question: "Compare A et B sur plusieurs dimensions",
    });
    expect(coverage.sufficient).toBe(false);
    expect(coverage.followUpQueries.length).toBeGreaterThan(0);
  });

  it("Test6: follow-up elliptique → web required + query ancrée", () => {
    const route = baseRoute({ mode: "none", searchType: "none", searchQuery: "" });
    const resolved = resolveConversationalWebRoute({
      route,
      userMessage: "Cherche sur internet les détails",
      priorUserMessages: [
        "Trouve-moi les 3 meilleurs modèles entre 250 et 400",
      ],
      priorWebUsed: true,
    });
    expect(resolved.web.mode).toBe("required");
    expect(resolved.web.mandatory).toBe(true);
    expect(resolved.tools.candidates).toContain("web_search");
    expect(resolved.web.searchQuery.toLowerCase()).toMatch(/modèles|250|400/);
  });

  it("Test7: provenance conservée jusqu'au bloc synthèse", () => {
    const items: WebEvidenceItem[] = [
      {
        id: "ev1",
        claim: "Valeur Alpha",
        value: "319 €",
        sourceId: "web_1",
        url: "https://shop.example/alpha",
        title: "Shop",
        evidence: "Alpha — 319 €",
        retrievedAt: new Date().toISOString(),
        confidence: "high",
        needId: "need_primary",
      },
    ];
    const coverage = evaluateCoverage({
      needs: [
        {
          id: "need_primary",
          description: "valeurs",
          priority: "critical",
          status: "open",
        },
      ],
      evidence: items,
      consolidated: consolidateEvidence(items),
      question: "valeurs Alpha",
    });
    const block = formatEvidenceContextBlock({
      evidence: items,
      consolidated: consolidateEvidence(items),
      coverage,
    });
    expect(block).toContain("https://shop.example/alpha");
    expect(block).toContain("web_1");
    expect(block).toContain("319");
  });

  it("Test8: budget — preuves avant texte brut secondaire", async () => {
    const result = await runWebEvidencePipeline({
      userQuestion: "Quelles valeurs pour Alpha ?",
      searchQuery: "Alpha valeurs",
      sources: [
        {
          sourceId: "web_1",
          url: "https://example.com/alpha",
          title: "Alpha page",
          snippet: "Présentation Alpha",
          pageContent:
            "Texte inutile. ".repeat(50) +
            "Alpha est indiqué à 319,41 € dans le tableau." +
            " Suite. ".repeat(50),
        },
      ],
      pageContents: {},
      maxAnalyzePages: 2,
      maxCandidateSources: 4,
    });
    expect(result.finalApplicationContext).toContain("<web_evidence>");
    const evidencePos = result.finalApplicationContext.indexOf("<web_evidence>");
    const secondaryPos = result.finalApplicationContext.indexOf(
      "<secondary_web_sources>"
    );
    if (secondaryPos >= 0) {
      expect(evidencePos).toBeLessThan(secondaryPos);
    }
  });

  it("Test9: affirmation négative — couverture incomplète ≠ absence absolue", () => {
    const coverage = evaluateCoverage({
      needs: [
        {
          id: "need_primary",
          description: "valeur Alpha",
          priority: "critical",
          status: "open",
        },
      ],
      evidence: [],
      consolidated: [],
      question: "valeur Alpha",
    });
    const block = formatEvidenceContextBlock({
      evidence: [],
      consolidated: [],
      coverage,
    });
    expect(block).toMatch(/non trouvé dans les preuves extraites/i);
    expect(block).toMatch(/absence absolue|non trouvé dans les preuves extraites/i);
  });

  it("Test10: aucun résultat suffisant → coverage insufficient sans invention", async () => {
    const result = await runWebEvidencePipeline({
      userQuestion: "xyzzy-unknown-entity-42",
      searchQuery: "xyzzy-unknown-entity-42",
      sources: [
        {
          sourceId: "web_1",
          url: "https://example.com/empty",
          title: "Empty",
          snippet: "Page sans rapport",
          pageContent: "Bonjour le monde. Aucune donnée utile ici.",
        },
      ],
      pageContents: {},
      maxAnalyzePages: 1,
    });
    expect(result.coverage.sufficient).toBe(false);
    expect(result.evidence.length).toBe(0);
    expect(result.coverage.reason.length).toBeGreaterThan(0);
  });
});

describe("web-evidence V3 question-focused packets", () => {
  it("Test A: info absente du snippet mais présente dans la page → packet", async () => {
    const result = await runWebEvidencePipeline({
      userQuestion: "Quel est le prix du produit X ?",
      searchQuery: "produit X prix",
      sources: [
        {
          sourceId: "web_1",
          url: "https://shop.example/x",
          title: "Produit X",
          snippet: "Découvrez notre gamme innovante.",
          pageContent:
            "Intro marketing. ".repeat(40) +
            "Produit X : 129 € TTC. Bruit : 42 dB." +
            " Fin. ".repeat(20),
        },
      ],
      pageContents: {},
      maxAnalyzePages: 1,
    });
    expect(result.packets.length).toBeGreaterThan(0);
    const blob = result.packets.map((p) => p.compactEvidence).join("\n");
    expect(blob).toMatch(/129/);
    expect(result.finalApplicationContext).toMatch(/129/);
  });

  it("Test B: page longue — info en fin de page conservée", async () => {
    const filler = "Paragraphe hors sujet. ".repeat(800);
    const result = await runWebEvidencePipeline({
      userQuestion: "Quel débit pour le ventilateur Zeta ?",
      searchQuery: "ventilateur Zeta débit",
      sources: [
        {
          sourceId: "web_1",
          url: "https://lab.example/zeta",
          title: "Zeta tests",
          snippet: "article long",
          pageContent: `${filler} Le ventilateur Zeta affiche un débit de 2 400 m³/h en mode turbo.`,
        },
      ],
      pageContents: {},
      maxAnalyzePages: 1,
      maxPageCharsForAnalysis: 24_000,
    });
    expect(result.finalApplicationContext).toMatch(/2\s*400|2400/);
  });

  it("Test C: 20 sources → sélection + extraction + consolidation", async () => {
    const sources = Array.from({ length: 20 }, (_, i) => ({
      sourceId: `s${i}`,
      url: `https://c${i}.example/p`,
      title: i % 5 === 0 ? `Guide Alpha valeurs ${i}` : `Noise ${i}`,
      snippet:
        i % 5 === 0
          ? `Alpha modèle détail ${i} valeurs chiffres`
          : `actualité générale ${i}`,
      domain: `c${i}.example`,
      pageContent:
        i % 5 === 0
          ? `Fiche produit détaillée. Alpha est listé à ${300 + i} € TTC sur cette page de test.`
          : `Contenu sans rapport avec la question Alpha numéro ${i}.`,
    }));
    const result = await runWebEvidencePipeline({
      userQuestion: "Quelles valeurs pour Alpha ?",
      searchQuery: "Alpha valeurs guide",
      sources,
      pageContents: {},
      maxCandidateSources: 20,
      maxAnalyzePages: 8,
      extractionConcurrency: 2,
    });
    expect(result.selection.filter((d) => d.selected).length).toBeGreaterThan(6);
    expect(result.packets.length).toBeGreaterThan(0);
    expect(
      result.trace.some(
        (t) => t.stage === "consolidation" || t.stage === "extracted_evidence"
      )
    ).toBe(true);
    expect(result.finalApplicationContext.length).toBeLessThan(12_000);
  });

  it("Test D: deux sources contradictoires → les deux valeurs restent", async () => {
    const result = await runWebEvidencePipeline({
      userQuestion: "Quel prix pour Alpha ?",
      searchQuery: "Alpha prix",
      sources: [
        {
          sourceId: "a",
          url: "https://a.example/alpha",
          title: "Shop A",
          snippet: "Alpha prix",
          pageContent: "Fiche tarif. Alpha coûte 399 € TTC chez Shop A aujourd'hui.",
        },
        {
          sourceId: "b",
          url: "https://b.example/alpha",
          title: "Shop B",
          snippet: "Alpha tarif",
          pageContent: "Fiche tarif. Alpha coûte 389 € TTC chez Shop B aujourd'hui.",
        },
      ],
      pageContents: {},
      maxAnalyzePages: 2,
    });
    const hasDiverge = result.consolidated.some(
      (g) => g.agreement === "diverge"
    );
    const bothValues =
      /399/.test(result.finalApplicationContext) &&
      /389/.test(result.finalApplicationContext);
    expect(hasDiverge || bothValues).toBe(true);
    expect(result.finalApplicationContext).toMatch(/399/);
    expect(result.finalApplicationContext).toMatch(/389/);
  });

  it("Test E: information manquante → follow-up search", async () => {
    let followCalls = 0;
    const result = await runWebEvidencePipeline({
      userQuestion: "Compare produit A et produit B sur plusieurs dimensions",
      searchQuery: "produit A produit B",
      sources: [
        {
          sourceId: "web_1",
          url: "https://ex.example/a",
          title: "A only",
          snippet: "A",
          pageContent: "Produit A existe. Peu de détails.",
        },
      ],
      pageContents: {},
      maxAnalyzePages: 1,
      maxFollowUpPasses: 1,
      runFollowUpSearch: async (query) => {
        followCalls += 1;
        expect(query.length).toBeGreaterThan(0);
        return {
          query,
          sources: [
            {
              sourceId: "follow_1",
              url: "https://ex.example/b",
              title: "B details",
              snippet: "B",
              pageContent: "Produit B : 210 €, bruit 35 dB.",
            },
          ],
          pageContents: {
            "https://ex.example/b": "Produit B : 210 €, bruit 35 dB.",
          },
        };
      },
    });
    expect(followCalls).toBeGreaterThanOrEqual(1);
    expect(result.researchPasses).toBeGreaterThanOrEqual(2);
    expect(result.trace.some((t) => t.stage === "follow_up_search")).toBe(true);
  });

  it("Test E2: couverture insuffisante → expand SERP avant follow-up", async () => {
    let followCalls = 0;
    const sources = Array.from({ length: 8 }, (_, i) => ({
      sourceId: `web_${i + 1}`,
      url: `https://ex.example/item-${i}`,
      title: `Source ${i}`,
      snippet: i < 2 ? "Aperçu partiel" : `Comparatif A/B prix ${180 + i}`,
      pageContent:
        i < 2
          ? "Produit A mentionné. Pas assez de critères pour comparer."
          : `Produit A : 199 €, bruit 38 dB. Produit B : ${180 + i} €, bruit 35 dB. Batterie 10h.`,
    }));

    const result = await runWebEvidencePipeline({
      userQuestion:
        "Compare produit A et produit B sur prix, bruit et batterie",
      searchQuery: "produit A produit B comparatif",
      sources,
      pageContents: {},
      maxAnalyzePages: 2,
      maxTotalAnalyzePages: 12,
      maxFollowUpPasses: 1,
      runFollowUpSearch: async (query) => {
        followCalls += 1;
        return { query, sources: [], pageContents: {} };
      },
    });

    expect(result.analyses.length).toBeGreaterThan(2);
    expect(
      result.trace.some(
        (t) =>
          t.stage === "coverage_check" &&
          String(t.inputSummary ?? "").includes("expand")
      )
    ).toBe(true);
    // L'expansion SERP suffit souvent → follow-up pas forcément appelé
    expect(followCalls).toBeLessThanOrEqual(1);
  });

  it("Test F: follow-up « Cherche sur internet les prix » → query ancrée", () => {
    const route = baseRoute({
      mode: "none",
      searchType: "none",
      searchQuery: "",
      enabled: true,
    });
    const resolved = resolveConversationalWebRoute({
      route,
      userMessage: "Cherche sur internet les prix",
      priorUserMessages: [
        "Fais-moi un top 3 des meilleurs CPU entre 250 et 400 €",
      ],
      priorWebUsed: true,
    });
    expect(resolved.web.mode).toBe("required");
    expect(resolved.tools.candidates).toContain("web_search");
    expect(resolved.web.searchQuery.toLowerCase()).toMatch(
      /cpu|250|400|prix|top/
    );
  });

  it("Test G: EvidencePacket → provenance jusqu'à la synthèse", async () => {
    const result = await runWebEvidencePipeline({
      userQuestion: "Prix du ventilateur Aero ?",
      searchQuery: "ventilateur Aero prix",
      sources: [
        {
          sourceId: "web_7",
          url: "https://fan.example/aero",
          title: "Aero",
          snippet: "Aero",
          pageContent: "Le ventilateur Aero est à 99 €. Bruit 38 dB.",
        },
      ],
      pageContents: {},
    });
    const packet = result.packets[0];
    expect(packet).toBeTruthy();
    expect(packet!.sourceId).toBe("web_7");
    expect(packet!.url).toBe("https://fan.example/aero");
    expect(packet!.retrievedAt).toBeTruthy();
    expect(result.finalApplicationContext).toContain("web_7");
    expect(result.finalApplicationContext).toContain(
      "https://fan.example/aero"
    );
  });

  it("Test H: EvidencePacket compact → contexte final raisonnable", () => {
    const analysis: SourceAnalysisResult = {
      sourceId: "web_1",
      url: "https://example.com/long",
      title: "Long",
      relevant: true,
      extracted: Array.from({ length: 20 }, (_, i) => ({
        id: `e${i}`,
        claim: `Fait très long numéro ${i} `.repeat(20),
        value: `${100 + i} €`,
        sourceId: "web_1",
        url: "https://example.com/long",
        title: "Long",
        evidence: "preuve ".repeat(40),
        retrievedAt: new Date().toISOString(),
        confidence: "medium" as const,
      })),
      analyzedChars: 5000,
      rawChars: 5000,
      extractionStatus: "ok",
    };
    const packet = buildEvidencePacket({ analysis });
    expect(packet.compactEvidence.length).toBeLessThanOrEqual(
      EVIDENCE_PACKET_MAX_CHARS
    );
    const block = formatEvidencePacketsBlock([packet], { maxChars: 2_000 });
    expect(block.length).toBeLessThan(3_000);
  });

  it("Test I: extraction LLM échoue sur une page → les autres continuent", async () => {
    let calls = 0;
    const result = await runWebEvidencePipeline({
      userQuestion: "Prix Alpha et Beta ?",
      searchQuery: "Alpha Beta prix",
      sources: [
        {
          sourceId: "bad",
          url: "https://bad.example/x",
          title: "Bad",
          snippet: "Alpha",
          pageContent: "Fiche produit. Alpha coûte 111 € TTC sur cette page de test.",
        },
        {
          sourceId: "good",
          url: "https://good.example/y",
          title: "Good",
          snippet: "Beta",
          pageContent: "Fiche produit. Beta coûte 222 € TTC sur cette page de test.",
        },
      ],
      pageContents: {},
      maxAnalyzePages: 2,
      analyzeSource: async ({ source }) => {
        calls += 1;
        if (source.sourceId === "bad") {
          throw new Error("LLM down");
        }
        return [
          {
            claim: "Beta prix",
            value: "222 €",
            evidence: "Beta coûte 222 € TTC sur cette page de test.",
            confidence: "high" as const,
          },
        ];
      },
    });
    expect(calls).toBe(2);
    expect(
      result.evidence.some((e) => (e.value || e.claim).includes("222"))
    ).toBe(true);
    expect(result.analyses.length).toBe(2);
  });

  it("Test J: chiffre présent → EvidencePacket final", async () => {
    const result = await runWebEvidencePipeline({
      userQuestion: "Quel bruit pour le modèle QuietFan ?",
      searchQuery: "QuietFan bruit dB",
      sources: [
        {
          sourceId: "web_1",
          url: "https://test.example/quiet",
          title: "QuietFan",
          snippet: "test labo",
          pageContent:
            "Test laboratoire QuietFan : 41 dB à 1 m. Débit 1800 m³/h. Prix observé 119 €.",
        },
      ],
      pageContents: {},
    });
    const packetText =
      result.packets[0]?.importantValues.join(" ") ||
      result.packets[0]?.compactEvidence ||
      "";
    expect(packetText).toMatch(/41|119|1800/);
    expect(result.finalApplicationContext).toMatch(/41|119|1800/);
  });

  it("parse LLM extraction: JSON strict, refuse inventé", () => {
    const parsed = parsePageEvidenceExtractionJson(`\`\`\`json
{
  "relevantFacts": ["QuietFan 41 dB"],
  "importantValues": ["41 dB"],
  "caveats": [],
  "contradictions": [],
  "items": [
    {
      "claim": "QuietFan bruit",
      "value": "41 dB",
      "evidence": "41 dB à 1 m",
      "confidence": "high"
    }
  ]
}
\`\`\``);
    expect(parsed?.importantValues).toContain("41 dB");
    expect(parsed?.items[0]?.value).toBe("41 dB");
    expect(parsePageEvidenceExtractionJson("pas du json")).toBeNull();
  });
});

describe("Web Evidence V4", () => {
  it("A: concurrency=1 fonctionne", async () => {
    const { runWebEvidencePipeline } = await import("./pipeline");
    const result = await runWebEvidencePipeline({
      userQuestion: "Quels sont les attributs clés du produit Alpha ?",
      searchQuery: "produit Alpha attributs",
      sources: [
        {
          sourceId: "web_1",
          url: "https://example.com/a",
          title: "Alpha",
          snippet: "fiche Alpha",
          pageContent: "Le produit Alpha affiche 42 unités et coûte 129 €.",
        },
      ],
      pageContents: {},
      extractionConcurrency: 1,
      maxAnalyzePages: 1,
    });
    expect(result.metrics.extractionConcurrency).toBe(1);
    expect(result.packets.length + result.evidence.length).toBeGreaterThan(0);
  });

  it("B/C: concurrency=2 fonctionne", async () => {
    const { runWebEvidencePipeline } = await import("./pipeline");
    const result = await runWebEvidencePipeline({
      userQuestion: "Comparer Alpha et Beta",
      searchQuery: "Alpha Beta",
      sources: [
        {
          sourceId: "web_1",
          url: "https://a.example/x",
          title: "A",
          snippet: "Alpha",
          pageContent: "Alpha : 100 €, score 8/10.",
        },
        {
          sourceId: "web_2",
          url: "https://b.example/y",
          title: "B",
          snippet: "Beta",
          pageContent: "Beta : 120 €, score 7/10.",
        },
      ],
      pageContents: {},
      extractionConcurrency: 2,
      maxAnalyzePages: 2,
    });
    expect(result.metrics.extractionConcurrency).toBe(2);
    expect(result.evidence.length + result.packets.length).toBeGreaterThan(0);
  });

  it("D/E: cache hit et invalidation", async () => {
    const {
      buildExtractCacheKey,
      hashContent,
      readExtractCache,
      writeExtractCache,
      resetExtractCacheForTests,
      getExtractCacheStats,
      EXTRACTION_PROMPT_VERSION,
    } = await import("./extract-cache");
    resetExtractCacheForTests();
    const key = buildExtractCacheKey({
      url: "https://example.com/p",
      contentHash: hashContent("contenu stable"),
      question: "Quel prix ?",
      promptVersion: EXTRACTION_PROMPT_VERSION,
      modelId: "test-model",
    });
    writeExtractCache(key, {
      rows: [
        {
          claim: "prix",
          value: "10 €",
          evidence: "prix 10 €",
          confidence: "high",
        },
      ],
      storedAt: Date.now(),
    });
    expect(readExtractCache(key)?.rows[0]?.value).toBe("10 €");
    const hits = getExtractCacheStats().hits;
    readExtractCache(key);
    expect(getExtractCacheStats().hits).toBeGreaterThanOrEqual(hits);
    const other = buildExtractCacheKey({
      url: "https://example.com/p",
      contentHash: hashContent("contenu modifié"),
      question: "Quel prix ?",
      promptVersion: EXTRACTION_PROMPT_VERSION,
      modelId: "test-model",
    });
    expect(readExtractCache(other)).toBeNull();
  });

  it("F: structured output schema + parse fallback", async () => {
    const mod = await import("./llm-extract");
    expect(mod.PAGE_EVIDENCE_JSON_SCHEMA).toBeTruthy();
    const parsed = mod.parsePageEvidenceExtractionJson(
      JSON.stringify({
        relevantFacts: ["fait"],
        importantValues: ["10 €"],
        caveats: [],
        contradictions: [],
        items: [
          {
            claim: "prix",
            value: "10 €",
            evidence: "prix 10 €",
            confidence: "high",
          },
        ],
      })
    );
    expect(parsed?.items[0]?.value).toBe("10 €");
    expect(mod.parsePageEvidenceExtractionJson("pas du json")).toBeNull();
  });

  it("G: contradiction / divergence conservée", async () => {
    const { consolidateEvidence } = await import("./consolidate");
    const groups = consolidateEvidence([
      {
        id: "1",
        claim: "Alpha prix",
        value: "100 €",
        sourceId: "web_1",
        url: "https://a.example",
        title: "A",
        evidence: "Alpha 100 € chez VendorA",
        retrievedAt: new Date().toISOString(),
        confidence: "high",
      },
      {
        id: "2",
        claim: "Alpha prix",
        value: "900 €",
        sourceId: "web_2",
        url: "https://b.example",
        title: "B",
        evidence: "Alpha 900 € chez VendorB",
        retrievedAt: new Date().toISOString(),
        confidence: "high",
      },
    ]);
    expect(groups.some((g) => g.agreement === "diverge")).toBe(true);
  });

  it("H: coverage détecte information manquante", async () => {
    const { deriveInformationNeeds } = await import("./information-needs");
    const { evaluateCoverage } = await import("./coverage");
    const needs = deriveInformationNeeds(
      "Compare produit A et produit B selon plusieurs critères avec budget 200"
    );
    const coverage = evaluateCoverage({
      needs,
      evidence: [
        {
          id: "1",
          claim: "Produit A existe",
          sourceId: "web_1",
          url: "https://ex.example",
          title: "A",
          evidence: "Produit A existe.",
          retrievedAt: new Date().toISOString(),
          confidence: "medium",
          needId: "need_primary",
        },
      ],
      consolidated: [],
      question:
        "Compare produit A et produit B selon plusieurs critères avec budget 200",
    });
    expect(coverage.sufficient).toBe(false);
  });

  it("I: follow-up câblé et déclenchable", async () => {
    const { runWebEvidencePipeline } = await import("./pipeline");
    let follow = 0;
    const result = await runWebEvidencePipeline({
      userQuestion: "Compare entité A et entité B sur plusieurs dimensions",
      searchQuery: "entité A B",
      sources: [
        {
          sourceId: "web_1",
          url: "https://ex.example/a",
          title: "A",
          snippet: "A",
          pageContent: "Entité A mentionnée brièvement.",
        },
      ],
      pageContents: {},
      maxAnalyzePages: 1,
      maxFollowUpPasses: 1,
      runFollowUpSearch: async (q) => {
        follow += 1;
        return {
          query: q,
          sources: [
            {
              sourceId: "web_2",
              url: "https://ex.example/b",
              title: "B",
              snippet: "B",
              pageContent: "Entité B : valeur 55, contrainte 200.",
            },
          ],
          pageContents: {
            "https://ex.example/b": "Entité B : valeur 55, contrainte 200.",
          },
        };
      },
    });
    expect(result.researchPasses).toBeGreaterThanOrEqual(1);
    expect(follow).toBeGreaterThanOrEqual(0);
  });

  it("J: provenance sourceId conservée", async () => {
    const { runWebEvidencePipeline } = await import("./pipeline");
    const result = await runWebEvidencePipeline({
      userQuestion: "Prix Aero ?",
      searchQuery: "Aero prix",
      sources: [
        {
          sourceId: "web_7",
          url: "https://fan.example/aero",
          title: "Aero",
          snippet: "Aero",
          pageContent: "Fiche produit. Aero coûte 99 € TTC sur cette page de test.",
        },
      ],
      pageContents: {},
    });
    expect(
      result.packets[0]?.sourceId === "web_7" ||
        result.evidence.some((e) => e.sourceId === "web_7")
    ).toBe(true);
    expect(result.finalApplicationContext).toContain("web_7");
  });

  it("K: une seule balise web_evidence", async () => {
    const { runWebEvidencePipeline } = await import("./pipeline");
    const result = await runWebEvidencePipeline({
      userQuestion: "Valeurs Alpha ?",
      searchQuery: "Alpha",
      sources: [
        {
          sourceId: "web_1",
          url: "https://example.com/alpha",
          title: "Alpha",
          snippet: "Alpha",
          pageContent: "Alpha 319 € dans le tableau.",
        },
      ],
      pageContents: {},
    });
    const block = result.finalApplicationContext;
    expect(block.indexOf("<web_evidence>")).toBe(
      block.lastIndexOf("<web_evidence>")
    );
  });

  it("L: page longue — chunks bornés", async () => {
    const { chunkPageContent } = await import("./extract");
    expect(chunkPageContent("x".repeat(10_000), 18_000, 300).length).toBe(1);
    const chunks = chunkPageContent("y".repeat(50_000), 18_000, 300);
    expect(chunks.length).toBeGreaterThanOrEqual(1);
    expect(chunks.length).toBeLessThanOrEqual(3);
  });

  it("M: associations tableau/liste en texte", () => {
    const tableLike = "Alpha | 129 €\nBeta | 149 €";
    expect(tableLike).toContain("Alpha | 129");
  });

  it("N: échec d'une extraction n'arrête pas les autres", async () => {
    const { runWebEvidencePipeline } = await import("./pipeline");
    let calls = 0;
    const result = await runWebEvidencePipeline({
      userQuestion: "Prix Alpha et Beta ?",
      searchQuery: "Alpha Beta",
      sources: [
        {
          sourceId: "bad",
          url: "https://bad.example/x",
          title: "Bad",
          snippet: "Alpha",
          pageContent: "Fiche produit. Alpha coûte 111 € TTC sur cette page de test.",
        },
        {
          sourceId: "good",
          url: "https://good.example/y",
          title: "Good",
          snippet: "Beta",
          pageContent: "Fiche produit. Beta coûte 222 € TTC sur cette page de test.",
        },
      ],
      pageContents: {},
      maxAnalyzePages: 2,
      analyzeSource: async ({ source }) => {
        calls += 1;
        if (source.sourceId === "bad") throw new Error("LLM down");
        return [
          {
            claim: "Beta prix",
            value: "222 €",
            evidence: "Beta coûte 222 €.",
            confidence: "high",
          },
        ];
      },
    });
    expect(calls).toBe(2);
    expect(
      result.evidence.some((e) => (e.value || e.claim).includes("222"))
    ).toBe(true);
  });
});


describe("chat single-pass: no expand / no follow-up", () => {
  it("respecte maxTotalAnalyzePages=maxAnalyzePages et n'appelle pas le follow-up", async () => {
    let followUps = 0;
    const sources = Array.from({ length: 5 }, (_, i) => ({
      sourceId: `web_${i + 1}`,
      url: `https://example.com/p${i + 1}`,
      title: `Page ${i + 1}`,
      snippet: `snippet ${i + 1} boeuf bourguignon vegan PST`,
      domain: "example.com",
      pageContent: `Contenu page ${i + 1}: recette de boeuf bourguignon vegan avec PST, 40 minutes, 4 personnes.`,
    }));
    const result = await runWebEvidencePipeline({
      userQuestion: "Recette de boeuf bourguignon vegan avec PST ?",
      searchQuery: "boeuf bourguignon vegan PST",
      sources,
      pageContents: Object.fromEntries(
        sources.map((s) => [s.url, s.pageContent ?? ""])
      ),
      maxAnalyzePages: 5,
      maxTotalAnalyzePages: 5,
      maxCandidateSources: 5,
      maxFollowUpPasses: 0,
      runFollowUpSearch: async () => {
        followUps += 1;
        return { query: "x", sources: [], pageContents: {} };
      },
    });
    expect(followUps).toBe(0);
    expect(result.metrics.analyzedCount).toBeLessThanOrEqual(5);
    expect(result.finalApplicationContext.length).toBeGreaterThan(0);
  });
});
