import { describe, expect, it } from "vitest";
import { buildContextPlan } from "@/lib/context/plan";
import { expandRetrievalQuery } from "@/lib/context/follow-up";
import {
  MEMORY_RANK_WEIGHTS,
  rankAndSelectMemories,
  recencyScore,
  scoreMemory,
} from "@/lib/memory/ranking";
import type { Memory } from "@/lib/db/schema";
import type { RouteDecision } from "@/lib/request-router/types";
import { EMPTY_EMAIL_ROUTE, EMPTY_FILES_ROUTE } from "@/lib/request-router/email-intent";

function baseRoute(over: Partial<RouteDecision> = {}): RouteDecision {
  return {
    source: "fast_path",
    knowledge: "static",
    web: {
      enabled: false,
      mode: "none",
      searchType: "none",
      wouldBeUseful: false,
      mandatory: false,
      autoSearch: false,
      searchQuery: "",
      reason: "test",
    },
    email: EMPTY_EMAIL_ROUTE,
    files: EMPTY_FILES_ROUTE,
    research: {},
    execution: { mode: "direct", suggestAgent: false },
    vision: { required: false, reason: "" },
    tools: { allowToolCalling: false, candidates: [] },
    temporal: {
      scope: "unspecified",
      userIntent: "none",
      isTimeSensitive: false,
      referenceYear: null,
      userMentionedYears: [],
      clock: {
        currentDate: "2026-09-02",
        currentDateTime: "02/09/2026 12:00:00",
        timezone: "Europe/Paris",
        currentYear: 2026,
        currentMonth: 9,
      },
    },
    confidence: 0.9,
    reason: "test",
    latencyMs: 1,
    ...over,
  };
}

function mem(
  partial: Partial<Memory> & Pick<Memory, "id" | "content">
): Memory {
  return {
    category: "other",
    importance: 0.7,
    embedding: null,
    createdAt: "2026-01-01T00:00:00.000Z",
    updatedAt: "2026-01-01T00:00:00.000Z",
    ...partial,
  };
}

describe("ContextPlan", () => {
  it("STATIC factuel → memoryBudget 0", () => {
    const plan = buildContextPlan({
      route: baseRoute({ knowledge: "static" }),
      message: "Pourquoi le ciel est bleu ?",
      hasAttachments: false,
      hasActiveFile: false,
      hasActiveMail: false,
    });
    expect(plan.memoryBudget).toBe(0);
    expect(plan.historyMode).toBe("minimal");
  });

  it("STATIC + signal perso → memoryBudget > 0", () => {
    const plan = buildContextPlan({
      route: baseRoute({ knowledge: "static" }),
      message: "Explique-moi ça en tenant compte de mes préférences",
      hasAttachments: false,
      hasActiveFile: false,
      hasActiveMail: false,
    });
    expect(plan.memoryBudget).toBeGreaterThan(0);
    expect(plan.personalRelevance).toBe("needed");
    expect(plan.answerContract).toBe("personal");
  });

  it("follow-up court active expandFollowUpQuery", () => {
    const plan = buildContextPlan({
      route: baseRoute(),
      message: "Et lui ?",
      hasAttachments: false,
      hasActiveFile: false,
      hasActiveMail: false,
      recentUserMessages: ["Parle-moi de Marie"],
    });
    expect(plan.expandFollowUpQuery).toBe(true);
  });
});

describe("Follow-up expansion", () => {
  it("current message is primary; assistant is secondary", () => {
    const r = expandRetrievalQuery({
      currentUserMessage: "Et le budget ?",
      previousUserMessages: ["Analyse ce PDF financier"],
      lastAssistantExcerpt: "Voici un résumé inventé du PDF…",
      activeEntityLabels: ["rapport.pdf"],
      expand: true,
    });
    expect(r.primaryQuery.startsWith("Et le budget ?")).toBe(true);
    expect(r.primaryQuery).toContain("rapport.pdf");
    expect(r.primaryQuery).toContain("Analyse ce PDF");
    expect(r.assistantHint).toContain("résumé");
    expect(r.retrievalQuery.indexOf("Et le budget ?")).toBe(0);
  });

  it("sans expand → query = current seulement", () => {
    const r = expandRetrievalQuery({
      currentUserMessage: "Bonjour",
      previousUserMessages: ["x"],
      lastAssistantExcerpt: "y",
      expand: false,
    });
    expect(r.retrievalQuery).toBe("Bonjour");
    expect(r.assistantHint).toBeNull();
  });
});

describe("Memory ranking", () => {
  it("weights sum to 1", () => {
    const sum = Object.values(MEMORY_RANK_WEIGHTS).reduce((a, b) => a + b, 0);
    expect(sum).toBeCloseTo(1, 5);
  });

  it("preference decays slower than temporary", () => {
    const old = "2024-01-01T00:00:00.000Z";
    const now = Date.parse("2026-09-02T00:00:00.000Z");
    const pref = recencyScore(old, "preference", now);
    const temp = recencyScore(old, "temporary", now);
    expect(pref).toBeGreaterThan(temp);
  });

  it("budget 0 excludes all", () => {
    const candidates = [
      mem({ id: "1", content: "User prefers French language responses" }),
      mem({ id: "2", content: "User owns a gaming PC" }),
    ];
    const { selected, excluded } = rankAndSelectMemories({
      candidates,
      primaryQuery: "French language",
      budget: 0,
    });
    expect(selected).toHaveLength(0);
    expect(excluded).toHaveLength(2);
  });

  it("selects higher lexical+entity over weak matches", () => {
    const candidates = [
      mem({
        id: "weak",
        content: "Likes tea",
        category: "preference",
        importance: 0.9,
        updatedAt: "2026-09-01T00:00:00.000Z",
      }),
      mem({
        id: "strong",
        content: "Working on Chatbot project with Next.js",
        category: "project",
        importance: 0.6,
        updatedAt: "2026-08-01T00:00:00.000Z",
      }),
    ];
    const ranked = candidates.map((memory) =>
      scoreMemory({
        memory,
        primaryQuery: "Chatbot project files",
        entityLabels: ["Chatbot"],
      })
    );
    ranked.sort((a, b) => b.score - a.score);
    expect(ranked[0]?.memory.id).toBe("strong");
  });
});
