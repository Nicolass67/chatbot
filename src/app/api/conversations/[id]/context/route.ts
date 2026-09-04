export const runtime = "nodejs";

import { loadConversationContextSnapshot } from "@/lib/context/load-conversation-context";
import { getSettings } from "@/lib/settings/service";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  if (id === "new") {
    const settings = await getSettings();
    return Response.json({
      conversationTokens: 0,
      contextLengthMax: settings.contextLength,
      budgetTokens: Math.floor(settings.contextLength * 0.9),
      usedPercent: 0,
      remainingPercent: 100,
      breakdown: {
        system: 0,
        memories: 0,
        summary: 0,
        documents: 0,
        tools: 0,
        messages: 0,
        images: 0,
      },
      includedMessageCount: 0,
      totalMessageCount: 0,
      hasSummary: false,
      estimator: "fallback",
    });
  }

  const url = new URL(request.url);
  const attachmentIds = url.searchParams.getAll("attachmentId");
  const query = url.searchParams.get("query") ?? undefined;

  const snapshot = await loadConversationContextSnapshot({
    conversationId: id,
    query: query ?? undefined,
    attachmentIds,
  });

  return Response.json(snapshot);
}
