export const runtime = "nodejs";

import { loadConversationMessagesPayload } from "@/lib/chat/load-conversation-messages";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const payload = await loadConversationMessagesPayload(id);
  return Response.json(payload);
}
