import type { MemoryIntentDecision } from "@/lib/memory/intent-classifier";
import { classifyMemoryIntent } from "@/lib/memory/intent-classifier-runtime";
import { logMemoryIntentDecision } from "@/lib/memory/logging";
import { buildObjectiveContext } from "./objective-context";
import { resolveRouteDecision } from "./route-request";
import type { RequestContext, RouteDecision } from "./types";

export interface RequestAnalysis {
  route: RouteDecision;
  memory: MemoryIntentDecision;
  latencyMs: number;
}

export async function analyzeRequest(
  ctx: RequestContext,
  options?: { memoryEnabled?: boolean }
): Promise<RequestAnalysis> {
  const started = Date.now();
  const objective = buildObjectiveContext(ctx);

  const [route, memory] = await Promise.all([
    resolveRouteDecision(ctx, { allowClassifier: true }),
    classifyMemoryIntent(ctx, objective, {
      memoryEnabled: options?.memoryEnabled,
    }),
  ]);

  logMemoryIntentDecision(memory, ctx);

  return {
    route,
    memory,
    latencyMs: Date.now() - started,
  };
}
