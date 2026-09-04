import type { ChatMessage, MessageContentPart } from "@/lib/runtime/types";

export interface TokenEstimator {
  estimate(text: string): number;
  estimateMessages(messages: ChatMessage[]): number;
}

export function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}

function estimateContent(
  content: string | MessageContentPart[] | null
): number {
  if (!content) return 0;
  if (typeof content === "string") return estimateTokens(content);
  return content.reduce((sum, part) => {
    if (part.type === "text" && part.text) return sum + estimateTokens(part.text);
    if (part.type === "image_url") return sum + 512;
    return sum;
  }, 0);
}

/** Fallback approximation — replace with model-specific tokenizer in V2 */
export class FallbackTokenEstimator implements TokenEstimator {
  estimate(text: string): number {
    return estimateTokens(text);
  }

  estimateMessages(messages: ChatMessage[]): number {
    return messages.reduce(
      (sum, m) => sum + estimateContent(m.content) + 4,
      0
    );
  }
}

export const tokenEstimator = new FallbackTokenEstimator();
