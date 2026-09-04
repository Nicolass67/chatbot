import { describe, expect, it } from "vitest";
import type { RuntimeClock } from "@/lib/runtime/clock";
import { buildRouteDecision } from "./decision-builder";
import { buildObjectiveContext } from "./objective-context";
import {
  EMAIL_INTENT_TOOL_MAP,
  emailIntentToTools,
  EMPTY_EMAIL_ROUTE,
  resolveEmailRouteBlock,
} from "./email-intent";
import { routeToEmailIntent } from "./route-request";
import {
  ROUTER_EVALUATION_DATASET,
} from "./evaluation-dataset";
import {
  buildDecisionFromMock,
  evaluateRouteDecision,
} from "./evaluate-router";
import type { SemanticClassification } from "./types";

const SEPT_2026_CLOCK: RuntimeClock = {
  currentDate: "2026-09-01",
  currentDateTime: "01/09/2026 12:00:00",
  timezone: "Europe/Paris",
  currentYear: 2026,
  currentMonth: 9,
};

function buildCtxFromCase(testCase: (typeof ROUTER_EVALUATION_DATASET)[number]) {
  return {
    message: testCase.message,
    webSearchEnabled: testCase.webSearchEnabled ?? true,
    emailEnabled: testCase.emailEnabled ?? false,
    emailConnected: testCase.emailConnected ?? false,
    chatMode: testCase.chatMode ?? ("chat" as const),
    imageCount: testCase.imageCount ?? 0,
    attachmentCount: testCase.imageCount ?? 0,
    modelId: "test-model",
    recentUserMessages: testCase.recentUserMessages,
    clock: SEPT_2026_CLOCK,
    modelCapabilities: {
      text: true,
      vision: true,
      toolCalling: true,
      reasoning: false,
    },
  };
}

describe("email intent mapping", () => {
  it("mappe chaque intent vers les bons tools", () => {
    expect(emailIntentToTools("list")).toEqual(["email_list"]);
    expect(emailIntentToTools("search")).toEqual(["email_search"]);
    expect(emailIntentToTools("analyze")).toEqual(["email_analyze"]);
    expect(emailIntentToTools("draft")).toEqual(["email_create_draft"]);
    expect(emailIntentToTools("none")).toEqual([]);
    expect(Object.keys(EMAIL_INTENT_TOOL_MAP)).toHaveLength(5);
  });

  it("resolveEmailRouteBlock distingue feature on/off et connecté", () => {
    expect(
      resolveEmailRouteBlock({
        emailEnabled: true,
        emailConnected: true,
        intent: "analyze",
      })
    ).toMatchObject({
      enabled: true,
      wouldBeUseful: true,
      intent: "analyze",
      suggestedTools: ["email_analyze"],
    });

    expect(
      resolveEmailRouteBlock({
        emailEnabled: true,
        emailConnected: false,
        intent: "analyze",
      })
    ).toMatchObject({
      enabled: false,
      wouldBeUseful: true,
    });

    expect(
      resolveEmailRouteBlock({
        emailEnabled: false,
        emailConnected: false,
        intent: "list",
      }).wouldBeUseful
    ).toBe(false);
  });
});

describe("email routing — dataset mocké", () => {
  const emailCases = ROUTER_EVALUATION_DATASET.filter(
    (testCase) => testCase.expected.emailIntent !== undefined
  );

  for (const testCase of emailCases) {
    it(`${testCase.id} → intent ${testCase.expected.emailIntent}`, () => {
      const decision = buildDecisionFromMock(buildCtxFromCase(testCase), testCase);
      const evalResult = evaluateRouteDecision(testCase, decision);

      expect(evalResult.emailIntentError, testCase.id).toBe(false);
      if (testCase.expected.emailWouldBeUseful !== undefined) {
        expect(evalResult.emailUsefulnessError, testCase.id).toBe(false);
      }

      if (testCase.expected.emailIntent && testCase.expected.emailIntent !== "none") {
        expect(decision.tools.candidates.some((t) => t.startsWith("email_"))).toBe(
          testCase.emailEnabled ?? false
        );
      }
    });
  }

  it("envoi direct classé draft — pas de tool send", () => {
    const testCase = ROUTER_EVALUATION_DATASET.find(
      (c) => c.id === "email-send-blocked"
    )!;
    const decision = buildDecisionFromMock(buildCtxFromCase(testCase), testCase);
    expect(decision.email.intent).toBe("draft");
    expect(decision.tools.candidates).not.toContain("email_send");
    expect(decision.tools.candidates).toContain("email_create_draft");
  });
});

describe("routeToEmailIntent", () => {
  it("expose les suggested tools pour le registry", () => {
    const classification: SemanticClassification = {
      knowledge: "current",
      web: { mode: "none", searchType: "none" },
      email: { intent: "search", searchQuery: "is:unread" },
      execution: "tool",
      vision: { required: false },
      tools: { allowToolCalling: true },
      confidence: 0.9,
      reason: "Recherche email",
    };

    const decision = buildRouteDecision({
      ctx: {
        message: "Emails non lus",
        webSearchEnabled: true,
        emailEnabled: true,
        emailConnected: true,
        chatMode: "chat",
        imageCount: 0,
        attachmentCount: 0,
        modelId: "",
        clock: SEPT_2026_CLOCK,
      },
      objective: buildObjectiveContext({
        message: "Emails non lus",
        webSearchEnabled: true,
        emailEnabled: true,
        emailConnected: true,
        chatMode: "chat",
        imageCount: 0,
        attachmentCount: 0,
        modelId: "",
        clock: SEPT_2026_CLOCK,
      }),
      classification,
      source: "llm_classifier",
      latencyMs: 50,
    });

    const emailIntent = routeToEmailIntent(decision);
    expect(emailIntent.allowTools).toBe(true);
    expect(emailIntent.suggestedTools).toEqual(["email_search"]);
    expect(emailIntent.searchQuery).toBe("is:unread");
  });

  it("EMPTY_EMAIL_ROUTE par défaut hors email", () => {
    expect(EMPTY_EMAIL_ROUTE.intent).toBe("none");
    expect(EMPTY_EMAIL_ROUTE.suggestedTools).toEqual([]);
  });
});
