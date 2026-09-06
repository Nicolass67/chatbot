import { describe, expect, it } from "vitest";
import {
  clearMisroutedFilesIntent,
  hasExplicitLocalFilesIntent,
  hasWebChannelIntent,
  resolveConversationalWebRoute,
  rewriteMisroutedFileSearchCalls,
} from "./conversational-web-resolution";
import type { RouteDecision } from "@/lib/request-router/types";

function baseRoute(overrides?: {
  webMode?: RouteDecision["web"]["mode"];
  filesIntent?: RouteDecision["files"]["intent"];
  candidates?: string[];
}): RouteDecision {
  const filesIntent = overrides?.filesIntent ?? "search";
  return {
    knowledge: "current",
    web: {
      enabled: true,
      mode: overrides?.webMode ?? "none",
      searchType: "none",
      wouldBeUseful: false,
      mandatory: false,
      autoSearch: false,
      searchQuery: "",
      reason: "test",
    },
    email: {
      enabled: false,
      wouldBeUseful: false,
      intent: "none",
      suggestedTools: [],
      reason: "n/a",
    },
    files: {
      enabled: true,
      wouldBeUseful: filesIntent !== "none",
      intent: filesIntent,
      suggestedTools: filesIntent === "none" ? [] : ["file_search"],
      searchQuery: filesIntent === "search" ? "restaurants" : undefined,
      reason: "test",
    },
    research: {},
    execution: { mode: "tool", suggestAgent: false },
    vision: { required: false, reason: "n/a" },
    tools: {
      allowToolCalling: true,
      candidates: overrides?.candidates ?? ["file_search"],
    },
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

describe("conversational-web-resolution — web vs files", () => {
  it("détecte « recherches » comme canal web", () => {
    expect(
      hasWebChannelIntent(
        "Oui recherches les adresses des restaurant vegans à Strasbourg mentionné avant"
      )
    ).toBe(true);
  });

  it("ne confond pas une recherche d'adresses avec des fichiers locaux", () => {
    expect(
      hasExplicitLocalFilesIntent(
        "Oui recherches les adresses des restaurant vegans à Strasbourg mentionné avant"
      )
    ).toBe(false);
  });

  it("retire files.intent quand canal web sans marqueur local", () => {
    const cleared = clearMisroutedFilesIntent(
      baseRoute({ webMode: "none", filesIntent: "search" }),
      "Oui recherches les adresses des restaurants vegan"
    );
    expect(cleared.files.intent).toBe("none");
    expect(cleared.tools.candidates).not.toContain("file_search");
  });

  it("conserve files.intent pour une vraie demande locale", () => {
    const kept = clearMisroutedFilesIntent(
      baseRoute({ webMode: "none", filesIntent: "search" }),
      "Recherche mon fichier facture PDF dans mes dossiers"
    );
    expect(kept.files.intent).toBe("search");
  });

  it("follow-up adresses restaurants → web required, pas file_search", () => {
    const resolved = resolveConversationalWebRoute({
      route: baseRoute({ webMode: "none", filesIntent: "search" }),
      userMessage:
        "Oui recherches les adresses des restaurant vegans à Strasbourg mentionné avant",
      priorUserMessages: [
        "Quels sont les meilleurs restaurants vegan à Strasbourg ?",
      ],
      priorWebUsed: true,
    });
    expect(resolved.web.mode).toBe("required");
    expect(resolved.files.intent).toBe("none");
    expect(resolved.tools.candidates).toContain("web_search");
    expect(resolved.tools.candidates).not.toContain("file_search");
  });

  it("réécrit file_search → web_search pour une demande internet", () => {
    const rewritten = rewriteMisroutedFileSearchCalls(
      [
        {
          tool: "file_search",
          input: { query: "restaurants vegan Strasbourg" },
        },
      ],
      "Oui recherches les adresses des restaurants vegan sur internet"
    );
    expect(rewritten[0]?.tool).toBe("web_search");
    expect(String(rewritten[0]?.input.query)).toContain("restaurants");
  });

  it("ne réécrit pas file_search pour une demande fichier locale", () => {
    const rewritten = rewriteMisroutedFileSearchCalls(
      [{ tool: "file_search", input: { query: "facture" } }],
      "Trouve mon fichier facture PDF"
    );
    expect(rewritten[0]?.tool).toBe("file_search");
  });
});
