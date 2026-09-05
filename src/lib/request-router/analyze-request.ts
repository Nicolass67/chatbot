import type { MemoryIntentDecision } from "@/lib/memory/intent-classifier";
import { buildObjectiveContext } from "./objective-context";
import { resolveRouteDecision } from "./route-request";
import type { RequestContext, RouteDecision } from "./types";

export interface RequestAnalysis {
  route: RouteDecision;
  memory: MemoryIntentDecision;
  latencyMs: number;
}

/**
 * Stub mémoire pré-stream : la décision réelle est reportée au
 * Memory Post-Processor (après `done`), pour ne pas retarder le TTFT.
 */
function deferredMemoryDecision(): MemoryIntentDecision {
  return {
    shouldRemember: false,
    memories: [],
    confidence: 0,
    source: "none",
    reason: "deferred_to_post_processor",
    latencyMs: 0,
  };
}

export async function analyzeRequest(
  ctx: RequestContext,
  _options?: { memoryEnabled?: boolean }
): Promise<RequestAnalysis> {
  const started = Date.now();
  void buildObjectiveContext(ctx);

  const route = await resolveRouteDecision(ctx, { allowClassifier: true });

  return {
    route,
    memory: deferredMemoryDecision(),
    latencyMs: Date.now() - started,
  };
}
