import { describe, expect, it } from "vitest";
import type { RuntimeClock } from "@/lib/runtime/clock";
import { conservativeFallback } from "./conservative-fallback";
import { buildObjectiveContext } from "./objective-context";
import { tryFastPath } from "./fast-path";
import { routeRequestSync } from "./route-request";
import {
  ROUTER_EVALUATION_CASE_COUNT,
  ROUTER_EVALUATION_DATASET,
} from "./evaluation-dataset";
import {
  aggregateEvaluationMetrics,
  buildDecisionFromMock,
  evaluateRouteDecision,
} from "./evaluate-router";
import { parseSemanticClassification } from "./semantic-classifier";

const SEPT_2026_CLOCK: RuntimeClock = {
  currentDate: "2026-09-01",
  currentDateTime: "01/09/2026 12:00:00",
  timezone: "Europe/Paris",
  currentYear: 2026,
  currentMonth: 9,
};

function route(message: string, extra: Partial<Parameters<typeof routeRequestSync>[0]> = {}) {
  return routeRequestSync({
    message,
    webSearchEnabled: true,
    chatMode: "chat",
    imageCount: 0,
    attachmentCount: 0,
    modelId: "",
    clock: SEPT_2026_CLOCK,
    ...extra,
  });
}

describe("tryFastPath", () => {
  it("message trop court → none", () => {
    const objective = buildObjectiveContext({
      message: "ok",
      webSearchEnabled: true,
      chatMode: "chat",
      imageCount: 0,
      attachmentCount: 0,
      modelId: "",
      clock: SEPT_2026_CLOCK,
    });
    const result = tryFastPath(objective);
    expect(result.hit).toBe(true);
    expect(result.classification?.web.mode).toBe("none");
  });

  it("commande web lexicale → pas de fast path (LLM décide)", () => {
    const objective = buildObjectiveContext({
      message: "Cherche sur Internet qui a gagné le match.",
      webSearchEnabled: true,
      chatMode: "chat",
      imageCount: 0,
      attachmentCount: 0,
      modelId: "",
      clock: SEPT_2026_CLOCK,
    });
    const result = tryFastPath(objective);
    expect(result.hit).toBe(false);
  });

  it("Web OFF → none", () => {
    const objective = buildObjectiveContext({
      message: "Quel est le prix actuel de la RTX 5090 ?",
      webSearchEnabled: false,
      chatMode: "chat",
      imageCount: 0,
      attachmentCount: 0,
      modelId: "",
      clock: SEPT_2026_CLOCK,
    });
    const result = tryFastPath(objective);
    expect(result.hit).toBe(true);
    expect(result.classification?.web.mode).toBe("none");
  });
});

describe("routeRequestSync — fallback objectif", () => {
  it("capitale de France → no web", () => {
    const decision = route("Quelle est la capitale de la France ?");
    expect(decision.web.mode).toBe("none");
    expect(decision.execution.mode).toBe("direct");
  });

  it("météo demain → web required (portée temporelle)", () => {
    const decision = route("Quel temps fera-t-il demain à Strasbourg ?");
    expect(decision.web.mode).toBe("required");
    expect(decision.web.mandatory).toBe(true);
  });

  it("explique DLSS → no web", () => {
    const decision = route("Explique le fonctionnement du DLSS.");
    expect(decision.web.mode).toBe("none");
  });

  it("prix RTX 5090 → web required (portée temporelle)", () => {
    const decision = route("Quel est le prix actuel de la RTX 5090 ?");
    expect(decision.web.mode).toBe("required");
    expect(decision.web.autoSearch).toBe(true);
  });

  it("cherche sur Internet → pas de fast path lexical (fallback sans LLM)", () => {
    const decision = route("Cherche sur Internet qui a gagné le match.");
    // Sans classifieur LLM, pas de déclenchement par mots-clés.
    expect(decision.source).toBe("fallback_conservative");
    expect(decision.web.mode).toBe("none");
  });

  it("équation → no web", () => {
    const decision = route("Résous cette équation : 2x + 5 = 15");
    expect(decision.web.mode).toBe("none");
  });

  it("Web OFF → jamais de recherche", () => {
    const decision = route("Quel est le prix actuel de la RTX 5090 ?", {
      webSearchEnabled: false,
    });
    expect(decision.web.mode).toBe("none");
    expect(decision.web.autoSearch).toBe(false);
  });

  it("mode agent → execution agent", () => {
    const decision = routeRequestSync({
      message: "Compare les GPU actuels",
      webSearchEnabled: true,
      chatMode: "agent",
      imageCount: 0,
      attachmentCount: 0,
      modelId: "",
      clock: SEPT_2026_CLOCK,
    });
    expect(decision.execution.mode).toBe("agent");
  });

  it("suivi conversationnel sans signal temporel → no web (LLM async décidera)", () => {
    const decision = route("Et la 5080 ?", {
      recentUserMessages: ["Quel est le prix actuel de la RTX 5090 ?"],
    });
    expect(decision.web.mode).toBe("none");
  });

  it("adversarial sondage conceptuel → no web", () => {
    const decision = route("Explique-moi ce qu'est un sondage");
    expect(decision.web.mode).toBe("none");
  });

  it("adversarial météo concept → no web", () => {
    const decision = route("Comment fonctionne la météo ?");
    expect(decision.web.mode).toBe("none");
  });
});

describe("conservativeFallback", () => {
  it("sans signal temporel → NO_WEB", () => {
    const objective = buildObjectiveContext({
      message: "Pourquoi les GPU utilisent-ils de la VRAM ?",
      webSearchEnabled: true,
      chatMode: "chat",
      imageCount: 0,
      attachmentCount: 0,
      modelId: "",
      clock: SEPT_2026_CLOCK,
    });
    const fb = conservativeFallback(objective);
    expect(fb.web.mode).toBe("none");
  });
});

describe("parseSemanticClassification", () => {
  it("parse un JSON classifier valide", () => {
    const parsed = parseSemanticClassification(
      '{"knowledge":"current","web":{"mode":"required","searchType":"single"},"execution":"tool","vision":{"required":false},"tools":{"allowToolCalling":true},"confidence":0.94,"reason":"données actuelles"}'
    );
    expect(parsed.web.mode).toBe("required");
    expect(parsed.confidence).toBe(0.94);
  });
});

describe("evaluation dataset (mock classifier)", () => {
  it("contient au moins 50 cas", () => {
    expect(ROUTER_EVALUATION_CASE_COUNT).toBeGreaterThanOrEqual(50);
  });

  it("calcule les métriques sur le dataset mocké", () => {
    const results = ROUTER_EVALUATION_DATASET.filter(
      (testCase) => testCase.mockClassification
    ).map((testCase) => ({
      testCase,
      decision: buildDecisionFromMock(
        {
          message: testCase.message,
          webSearchEnabled: testCase.webSearchEnabled ?? true,
          emailEnabled: testCase.emailEnabled ?? false,
          emailConnected: testCase.emailConnected ?? false,
          chatMode: testCase.chatMode ?? "chat",
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
        },
        testCase
      ),
    }));

    const metrics = aggregateEvaluationMetrics(results);

    expect(metrics.webFalseNegatives).toBe(0);
    expect(metrics.webRequiredRecall).toBe(1);
    expect(metrics.total).toBeGreaterThanOrEqual(50);

    expect(metrics.emailIntentErrors).toBe(0);

    for (const { testCase, decision } of results) {
      const evalResult = evaluateRouteDecision(testCase, decision);
      expect(evalResult.webFn, `FN on ${testCase.id}`).toBe(false);
    }
  });

  it("cas obligatoires adversariaux", () => {
    const mandatoryIds = [
      "adversarial-sondage-concept",
      "adversarial-meteo-concept",
      "current-tennis",
      "context-followup-5080",
    ];

    for (const id of mandatoryIds) {
      const testCase = ROUTER_EVALUATION_DATASET.find((c) => c.id === id);
      expect(testCase).toBeDefined();
      if (!testCase?.mockClassification) continue;
      const decision = buildDecisionFromMock(
        {
          message: testCase.message,
          webSearchEnabled: true,
          emailEnabled: testCase.emailEnabled ?? false,
          emailConnected: testCase.emailConnected ?? false,
          chatMode: "chat",
          imageCount: testCase.imageCount ?? 0,
          attachmentCount: testCase.imageCount ?? 0,
          modelId: "test-model",
          recentUserMessages: testCase.recentUserMessages,
          clock: SEPT_2026_CLOCK,
        },
        testCase
      );
      const result = evaluateRouteDecision(testCase, decision);
      if (id.startsWith("adversarial")) {
        expect(decision.web.mode, id).toBe("none");
      } else {
        expect(decision.web.mode, id).toBe("required");
        expect(result.webFn, id).toBe(false);
      }
    }
  });
});

describe("formatWebSearchFailureBlock", () => {
  it("échecs web documentés pour injection LLM", async () => {
    const { formatWebSearchFailureBlock } = await import(
      "@/lib/agent/context-builder"
    );
    for (const status of ["provider_error", "timeout", "no_results"] as const) {
      const block = formatWebSearchFailureBlock(
        "prix RTX 5090",
        status,
        `Échec ${status}`
      );
      expect(block).toContain(`status="${status}"`);
      expect(block).toContain("Ne pas inventer");
    }
  });
});
