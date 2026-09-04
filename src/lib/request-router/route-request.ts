import { getRuntimeClock } from "@/lib/runtime/clock";
import { buildRouteDecision } from "./decision-builder";
import { conservativeFallback } from "./conservative-fallback";
import { tryFastPath } from "./fast-path";
import { logRouteDecision } from "./logging";
import { buildObjectiveContext } from "./objective-context";
import {
  CLASSIFIER_ACCEPT_CONFIDENCE,
  classifySemantic,
  shouldUseSemanticClassifier,
} from "./semantic-classifier-runtime";
import type { RequestContext, RouteDecision } from "./types";

export { CLASSIFIER_ACCEPT_CONFIDENCE };

function enrichContext(ctx: RequestContext): RequestContext {
  return { ...ctx, clock: ctx.clock ?? getRuntimeClock() };
}

async function routeInternal(
  ctx: RequestContext,
  options: { allowClassifier: boolean }
): Promise<RouteDecision> {
  const started = Date.now();
  const enriched = enrichContext(ctx);
  const objective = buildObjectiveContext(enriched);

  const fast = tryFastPath(objective);
  if (fast.hit && fast.classification) {
    const decision = buildRouteDecision({
      ctx: enriched,
      objective,
      classification: fast.classification,
      source: "fast_path",
      latencyMs: Date.now() - started,
    });
    logRouteDecision(decision, enriched);
    return decision;
  }

  if (options.allowClassifier && shouldUseSemanticClassifier(enriched)) {
    try {
      const classification = await classifySemantic(enriched, objective);
      if (classification.confidence >= CLASSIFIER_ACCEPT_CONFIDENCE) {
        const decision = buildRouteDecision({
          ctx: enriched,
          objective,
          classification,
          source: "llm_classifier",
          latencyMs: Date.now() - started,
        });
        logRouteDecision(decision, enriched);
        return decision;
      }
    } catch {
      // fallback below
    }
  }

  const fallback = conservativeFallback(objective);
  const decision = buildRouteDecision({
    ctx: enriched,
    objective,
    classification: fallback,
    source: "fallback_conservative",
    latencyMs: Date.now() - started,
  });
  logRouteDecision(decision, enriched);
  return decision;
}

export function routeRequestSync(ctx: RequestContext): RouteDecision {
  const started = Date.now();
  const enriched = enrichContext(ctx);
  const objective = buildObjectiveContext(enriched);

  const fast = tryFastPath(objective);
  if (fast.hit && fast.classification) {
    const decision = buildRouteDecision({
      ctx: enriched,
      objective,
      classification: fast.classification,
      source: "fast_path",
      latencyMs: Date.now() - started,
    });
    logRouteDecision(decision, enriched);
    return decision;
  }

  const fallback = conservativeFallback(objective);
  const decision = buildRouteDecision({
    ctx: enriched,
    objective,
    classification: fallback,
    source: "fallback_conservative",
    latencyMs: Date.now() - started,
  });
  logRouteDecision(decision, enriched);
  return decision;
}

export async function routeRequest(ctx: RequestContext): Promise<RouteDecision> {
  return routeInternal(ctx, { allowClassifier: true });
}

/** Routage interne (utilisé par analyzeRequest en parallèle). */
export async function resolveRouteDecision(
  ctx: RequestContext,
  options: { allowClassifier: boolean } = { allowClassifier: true }
): Promise<RouteDecision> {
  return routeInternal(ctx, options);
}

export function routeToWebSearchIntent(route: RouteDecision) {
  return {
    settingEnabled: route.web.enabled,
    queryUseful: route.web.wouldBeUseful,
    allowed: route.web.enabled && route.web.wouldBeUseful,
    autoSearch: route.web.autoSearch,
    searchQuery: route.web.searchQuery,
  };
}

export function routeToEmailIntent(route: RouteDecision) {
  return {
    featureEnabled: route.email.wouldBeUseful || route.email.intent !== "none",
    connected: route.email.enabled,
    wouldBeUseful: route.email.wouldBeUseful,
    intent: route.email.intent,
    suggestedTools: route.email.suggestedTools,
    searchQuery: route.email.searchQuery,
    allowTools: route.email.wouldBeUseful,
  };
}
