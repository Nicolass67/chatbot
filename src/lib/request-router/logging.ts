import type { RequestContext, RouteDecision } from "./types";

function truncateMessage(message: string, max = 120): string {
  const trimmed = message.trim();
  if (trimmed.length <= max) return trimmed;
  return `${trimmed.slice(0, max)}…`;
}

export function logRouteDecision(
  decision: RouteDecision,
  ctx: RequestContext
): void {
  if (process.env.NODE_ENV === "production") return;

  const lines = [
    "[ROUTER]",
    `source=${decision.source}`,
    `knowledge=${decision.knowledge}`,
    `web=${decision.web.mode}`,
    `email=${decision.email.intent}${decision.email.enabled ? " (connected)" : ""}`,
    `searchType=${decision.web.searchType}${decision.web.mandatory ? " (mandatory)" : ""}`,
    `execution=${decision.execution.mode}`,
    `vision=${decision.vision.required}`,
    `confidence=${decision.confidence.toFixed(2)}`,
    `latency_ms=${decision.latencyMs}`,
    `reason="${decision.reason}"`,
    `message: ${truncateMessage(ctx.message)}`,
  ];

  console.log(lines.join("\n"));
}
