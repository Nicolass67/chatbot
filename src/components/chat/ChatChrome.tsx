"use client";

import { useState, type ReactNode } from "react";
import { usePathname, useRouter } from "next/navigation";
import { Sidebar } from "@/components/layout/Sidebar";
import { MobileDrawer } from "@/components/layout/MobileDrawer";
import { ChatMobileNavProvider } from "@/components/chat/ChatMobileNavContext";
import { useConversations } from "@/components/chat/ConversationsProvider";
import { invalidateCachedMessages } from "@/lib/client/conversation-messages-cache";

/**
 * Shell chat persistant : sidebar desktop ne remonte pas entre /chat/[id].
 * Évite le saut de largeur du panneau redimensionnable.
 */
export function ChatChrome({ children }: { children: ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const {
    conversations,
    conversationsLoaded,
    refreshConversations,
    setConversations,
  } = useConversations();
  const [drawerOpen, setDrawerOpen] = useState(false);

  const handleNewChat = () => {
    setDrawerOpen(false);
    if (pathname === "/chat/new") {
      router.replace("/chat/new");
      router.refresh();
      return;
    }
    router.push("/chat/new");
  };

  const handleDelete = async (id: string) => {
    const viewing =
      pathname === `/chat/${id}` ||
      (typeof window !== "undefined" &&
        window.location.pathname === `/chat/${id}`);
    const res = await fetch(`/api/conversations/${id}`, { method: "DELETE" });
    if (!res.ok) return;

    invalidateCachedMessages(id);
    setConversations((prev) => prev.filter((c) => c.id !== id));
    await refreshConversations({ bust: true });

    if (viewing) {
      router.replace("/chat/new");
    }
  };

  const handleRename = async (id: string, newTitle: string) => {
    await fetch(`/api/conversations/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title: newTitle }),
    });
    setConversations((prev) =>
      prev.map((c) => (c.id === id ? { ...c, title: newTitle } : c))
    );
    void refreshConversations({ bust: true });
  };

  const sidebarProps = {
    conversations,
    conversationsLoaded,
    onNewChat: handleNewChat,
    onDelete: handleDelete,
    onRename: handleRename,
  };

  const mobileNav = {
    open: drawerOpen,
    onToggle: () => setDrawerOpen((o) => !o),
    onClose: () => setDrawerOpen(false),
  };

  return (
    <ChatMobileNavProvider value={mobileNav}>
      <div className="ambient-canvas flex h-dvh min-h-dvh overflow-hidden">
        <div className="hidden py-2 pl-2 md:flex">
          <Sidebar {...sidebarProps} />
        </div>

        <MobileDrawer
          open={drawerOpen}
          onClose={() => setDrawerOpen(false)}
          {...sidebarProps}
        />

        <div className="flex min-w-0 flex-1 flex-col">{children}</div>
      </div>
    </ChatMobileNavProvider>
  );
}
