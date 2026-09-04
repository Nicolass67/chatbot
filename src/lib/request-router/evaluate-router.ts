import { buildRouteDecision } from "./decision-builder";
import { buildObjectiveContext } from "./objective-context";
import type { EvaluationCase, RequestContext, RouteDecision } from "./types";

export interface RouterEvaluationMetrics {
  total: number;
  webRequiredPrecision: number;
  webRequiredRecall: number;
  webFalseNegatives: number;
  webFalsePositives: number;
  researchPrecision: number;
  researchErrors: number;
  visionPrecision: number;
  visionErrors: number;
  agentPrecision: number;
  agentErrors: number;
  emailIntentPrecision: number;
  emailIntentErrors: number;
  fastPathCount: number;
  classifierCount: number;
  fallbackCount: number;
  classifierLatencyP50: number;
  classifierLatencyP95: number;
}

function percentile(values: number[], p: number): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const idx = Math.min(
    sorted.length - 1,
    Math.max(0, Math.ceil((p / 100) * sorted.length) - 1)
  );
  return sorted[idx] ?? 0;
}

function expectedWebRequired(expected: EvaluationCase["expected"]): boolean {
  return expected.webMode === "required";
}

function actualWebRequired(decision: RouteDecision): boolean {
  return decision.web.mode === "required";
}

export function evaluateRouteDecision(
  testCase: EvaluationCase,
  decision: RouteDecision
): {
  webFn: boolean;
  webFp: boolean;
  researchError: boolean;
  visionError: boolean;
  agentError: boolean;
  emailIntentError: boolean;
  emailUsefulnessError: boolean;
} {
  const expectedReq = expectedWebRequired(testCase.expected);
  const actualReq = actualWebRequired(decision);

  const webFn = expectedReq && !actualReq;
  const webFp = !expectedReq && actualReq;

  const researchError =
    testCase.expected.searchType !== undefined &&
    decision.web.searchType !== testCase.expected.searchType;

  const visionError =
    testCase.expected.vision !== undefined &&
    decision.vision.required !== testCase.expected.vision;

  const agentError =
    testCase.expected.execution !== undefined &&
    decision.execution.mode !== testCase.expected.execution;

  const emailIntentError =
    testCase.expected.emailIntent !== undefined &&
    decision.email.intent !== testCase.expected.emailIntent;

  const emailUsefulnessError =
    testCase.expected.emailWouldBeUseful !== undefined &&
    decision.email.wouldBeUseful !== testCase.expected.emailWouldBeUseful;

  return {
    webFn,
    webFp,
    researchError,
    visionError,
    agentError,
    emailIntentError,
    emailUsefulnessError,
  };
}

export function buildDecisionFromMock(
  ctx: RequestContext,
  testCase: EvaluationCase
): RouteDecision {
  if (!testCase.mockClassification) {
    throw new Error(`Missing mockClassification for ${testCase.id}`);
  }
  const objective = buildObjectiveContext(ctx);
  return buildRouteDecision({
    ctx,
    objective,
    classification: testCase.mockClassification,
    source: "llm_classifier",
    latencyMs: 120,
  });
}

export function aggregateEvaluationMetrics(
  results: Array<{
    testCase: EvaluationCase;
    decision: RouteDecision;
  }>
): RouterEvaluationMetrics {
  let tp = 0;
  let fp = 0;
  let fn = 0;
  let researchErrors = 0;
  let visionErrors = 0;
  let agentErrors = 0;
  let emailIntentErrors = 0;
  let fastPathCount = 0;
  let classifierCount = 0;
  let fallbackCount = 0;
  const classifierLatencies: number[] = [];

  for (const { testCase, decision } of results) {
    const evalResult = evaluateRouteDecision(testCase, decision);
    if (expectedWebRequired(testCase.expected) && actualWebRequired(decision)) {
      tp++;
    }
    if (evalResult.webFp) fp++;
    if (evalResult.webFn) fn++;
    if (evalResult.researchError) researchErrors++;
    if (evalResult.visionError) visionErrors++;
    if (evalResult.agentError) agentErrors++;
    if (evalResult.emailIntentError) emailIntentErrors++;

    if (decision.source === "fast_path") fastPathCount++;
    if (decision.source === "llm_classifier") {
      classifierCount++;
      classifierLatencies.push(decision.latencyMs);
    }
    if (decision.source === "fallback_conservative") fallbackCount++;
  }

  const precisionDenom = tp + fp;
  const recallDenom = tp + fn;

  return {
    total: results.length,
    webRequiredPrecision: precisionDenom > 0 ? tp / precisionDenom : 1,
    webRequiredRecall: recallDenom > 0 ? tp / recallDenom : 1,
    webFalseNegatives: fn,
    webFalsePositives: fp,
    researchPrecision:
      1 -
      researchErrors /
        Math.max(
          1,
          results.filter((r) => r.testCase.expected.searchType === "research")
            .length
        ),
    researchErrors,
    visionPrecision:
      1 -
      visionErrors /
        Math.max(
          1,
          results.filter((r) => r.testCase.expected.vision !== undefined).length
        ),
    visionErrors,
    agentPrecision:
      1 -
      agentErrors /
        Math.max(
          1,
          results.filter((r) => r.testCase.expected.execution === "agent").length
        ),
    agentErrors,
    emailIntentPrecision:
      1 -
      emailIntentErrors /
        Math.max(
          1,
          results.filter((r) => r.testCase.expected.emailIntent !== undefined)
            .length
        ),
    emailIntentErrors,
    fastPathCount,
    classifierCount,
    fallbackCount,
    classifierLatencyP50: percentile(classifierLatencies, 50),
    classifierLatencyP95: percentile(classifierLatencies, 95),
  };
}
