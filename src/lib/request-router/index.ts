export type {
  EvaluationCase,
  EmailIntent,
  FileIntent,
  ExecutionMode,
  KnowledgeNeed,
  ObjectiveContext,
  RequestContext,
  RouteDecision,
  RouteSource,
  SemanticClassification,
  WebMode,
  WebSearchType,
} from "./types";

export {
  analyzeRequest,
  type RequestAnalysis,
} from "./analyze-request";

export {
  routeRequest,
  routeRequestSync,
  routeToWebSearchIntent,
  routeToEmailIntent,
  CLASSIFIER_ACCEPT_CONFIDENCE,
} from "./route-request";

export {
  EMAIL_INTENT_TOOL_MAP,
  EMPTY_EMAIL_ROUTE,
  EMPTY_FILES_ROUTE,
  emailIntentToTools,
  resolveEmailRouteBlock,
} from "./email-intent";
export { buildObjectiveContext } from "./objective-context";
export { tryFastPath } from "./fast-path";
export { conservativeFallback } from "./conservative-fallback";
export { buildRouteDecision } from "./decision-builder";
export {
  buildClassifierSystemPrompt,
  buildClassifierUserPrompt,
  parseSemanticClassification,
  semanticClassificationSchema,
} from "./semantic-classifier";
export {
  classifySemantic,
  shouldUseSemanticClassifier,
  CLASSIFIER_TIMEOUT_MS,
  CLASSIFIER_MAX_TOKENS,
} from "./semantic-classifier-runtime";
export {
  ROUTER_EVALUATION_DATASET,
  ROUTER_EVALUATION_CASE_COUNT,
} from "./evaluation-dataset";
export {
  aggregateEvaluationMetrics,
  buildDecisionFromMock,
  evaluateRouteDecision,
  type RouterEvaluationMetrics,
} from "./evaluate-router";
