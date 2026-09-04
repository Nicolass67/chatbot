import type { RequestContext } from "@/lib/request-router/types";
import type { MemoryIntentDecision } from "./intent-classifier";

function truncateMessage(message: string, max = 120): string {
  const trimmed = message.trim();
  if (trimmed.length <= max) return trimmed;
  return `${trimmed.slice(0, max)}…`;
}

export function logMemoryIntentDecision(
  decision: MemoryIntentDecision,
  ctx: RequestContext
): void {
  if (process.env.NODE_ENV === "production") return;

  const lines = [
    "[MEMORY]",
    `source=${decision.source}`,
    `shouldRemember=${decision.shouldRemember}`,
    `memories=${decision.memories.length}`,
    `confidence=${decision.confidence.toFixed(2)}`,
    `latency_ms=${decision.latencyMs}`,
    `reason="${decision.reason}"`,
    `message: ${truncateMessage(ctx.message)}`,
  ];

  console.log(lines.join("\n"));
}
