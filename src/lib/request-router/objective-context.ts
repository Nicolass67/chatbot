import { analyzeTemporalContext } from "@/lib/agent/temporal";
import { getRuntimeClock } from "@/lib/runtime/clock";
import type { ModelCapabilities } from "@/lib/runtime/types";
import type { ObjectiveContext, RequestContext } from "./types";

const DEFAULT_CAPABILITIES: ModelCapabilities = {
  text: true,
  vision: false,
  toolCalling: true,
  reasoning: false,
};

function buildConversationalContext(recent: string[]): string | undefined {
  const cleaned = recent.map((m) => m.trim()).filter(Boolean);
  if (cleaned.length === 0) return undefined;
  return cleaned.slice(-2).join("\n---\n");
}

export function buildObjectiveContext(ctx: RequestContext): ObjectiveContext {
  const clock = ctx.clock ?? getRuntimeClock();
  const trimmedMessage = ctx.message.trim();
  const recentUserMessages = (ctx.recentUserMessages ?? [])
    .map((m) => m.trim())
    .filter(Boolean);

  return {
    clock,
    temporal: analyzeTemporalContext(trimmedMessage, clock),
    message: ctx.message,
    trimmedMessage,
    webSearchEnabled: ctx.webSearchEnabled,
    chatMode: ctx.chatMode,
    imageCount: ctx.imageCount,
    attachmentCount: ctx.attachmentCount,
    hasAttachments: ctx.imageCount > 0 || ctx.attachmentCount > 0,
    modelId: ctx.modelId,
    modelCapabilities: ctx.modelCapabilities ?? DEFAULT_CAPABILITIES,
    recentUserMessages,
    conversationalContext: buildConversationalContext(recentUserMessages),
    // Plus de signaux lexicaux : le classifieur LLM décide des outils.
    explicitWebCommand: false,
    conversationalSkip: false,
    emailEnabled: ctx.emailEnabled ?? false,
    emailConnected: ctx.emailConnected ?? false,
    filesEnabled: ctx.filesEnabled ?? false,
    filesConfigured: ctx.filesConfigured ?? false,
    toolChannel: ctx.toolChannel,
  };
}
