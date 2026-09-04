import { ConversationsProvider } from "@/components/chat/ConversationsProvider";
import { ChatChrome } from "@/components/chat/ChatChrome";

export default function ChatLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <ConversationsProvider>
      <ChatChrome>{children}</ChatChrome>
    </ConversationsProvider>
  );
}
