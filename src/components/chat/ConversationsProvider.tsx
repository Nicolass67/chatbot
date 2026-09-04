"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import type { ConversationItem } from "@/components/layout/Sidebar";

interface ConversationsContextValue {
  conversations: ConversationItem[];
  conversationsLoaded: boolean;
  refreshConversations: (opts?: { bust?: boolean }) => Promise<void>;
  setConversations: React.Dispatch<React.SetStateAction<ConversationItem[]>>;
}

const ConversationsContext = createContext<ConversationsContextValue | null>(
  null
);

/**
 * Soft refresh: use cache when warm. Hard refresh after mutations.
 */
export function ConversationsProvider({ children }: { children: ReactNode }) {
  const [conversations, setConversations] = useState<ConversationItem[]>([]);
  const [conversationsLoaded, setConversationsLoaded] = useState(false);

  const refreshConversations = useCallback(async (opts?: { bust?: boolean }) => {
    const { cachedGetJson } = await import("@/lib/client/fetch-cache");
    const res = await cachedGetJson<ConversationItem[]>("/api/conversations", {
      ttlMs: 10_000,
      bust: opts?.bust,
    });
    if (res.ok) {
      setConversations(res.data);
    }
    setConversationsLoaded(true);
  }, []);

  useEffect(() => {
    void refreshConversations();
  }, [refreshConversations]);

  return (
    <ConversationsContext.Provider
      value={{
        conversations,
        conversationsLoaded,
        refreshConversations,
        setConversations,
      }}
    >
      {children}
    </ConversationsContext.Provider>
  );
}

export function useConversations() {
  const ctx = useContext(ConversationsContext);
  if (!ctx) {
    throw new Error("useConversations must be used within ConversationsProvider");
  }
  return ctx;
}
