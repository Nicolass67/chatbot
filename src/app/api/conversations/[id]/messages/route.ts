export const runtime = "nodejs";

import { loadConversationMessagesPayload } from "@/lib/chat/load-conversation-messages";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const url = new URL(request.url);
  const limitRaw = url.searchParams.get("limit");
  const beforeId =
    url.searchParams.get("beforeId")?.trim() ||
    url.searchParams.get("before")?.trim() ||
    undefined;

  let limit: number | undefined;
  if (limitRaw != null && limitRaw !== "") {
    const n = Number.parseInt(limitRaw, 10);
    if (Number.isFinite(n)) limit = n;
  }

  const payload = await loadConversationMessagesPayload(id, {
    limit,
    beforeId,
  });
  return Response.json(payload);
}
