"use client";

import { createContext, useContext, type ReactNode } from "react";

export interface ChatMobileNavValue {
  open: boolean;
  onToggle: () => void;
  onClose: () => void;
}

const ChatMobileNavContext = createContext<ChatMobileNavValue | null>(null);

export function ChatMobileNavProvider({
  value,
  children,
}: {
  value: ChatMobileNavValue;
  children: ReactNode;
}) {
  return (
    <ChatMobileNavContext.Provider value={value}>
      {children}
    </ChatMobileNavContext.Provider>
  );
}

export function useChatMobileNav() {
  return useContext(ChatMobileNavContext);
}
