import { eq } from "drizzle-orm";
import { notFound } from "next/navigation";
import { ChatView } from "@/components/chat/ChatView";
import { loadConversationMessagesPayload } from "@/lib/chat/load-conversation-messages";
import { getDb } from "@/lib/db";
import { conversations } from "@/lib/db/schema";

export const runtime = "nodejs";

export default async function ChatPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  if (id === "new") {
    return (
      <ChatView conversationId="new" initialTitle="Nouvelle conversation" />
    );
  }

  const db = getDb();
  const [conv, messagesPayload] = await Promise.all([
    db.query.conversations.findFirst({
      where: eq(conversations.id, id),
    }),
    loadConversationMessagesPayload(id),
  ]);

  if (!conv) notFound();

  return (
    <ChatView
      conversationId={id}
      initialTitle={conv.title}
      initialReasoningEffort={conv.reasoningEffort}
      initialChatMode={conv.chatMode as "chat" | "agent"}
      initialMessages={
        messagesPayload.messages as Parameters<
          typeof ChatView
        >[0]["initialMessages"]
      }
    />
  );
}
