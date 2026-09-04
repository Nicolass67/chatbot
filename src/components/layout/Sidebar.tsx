"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import {
  Settings,
  Trash2,
  Pencil,
  Download,
  Plus,
  MoreHorizontal,
} from "lucide-react";
import { IconButton } from "@/components/ui/IconButton";
import {
  MobileBottomSheet,
  MobileSheetAction,
} from "@/components/ui/MobileBottomSheet";
import { PanelResizeHandle } from "@/components/ui/PanelResizeHandle";
import { useResizableWidth } from "@/hooks/useResizableWidth";
import { cn } from "@/lib/utils/cn";

export interface ConversationItem {
  id: string;
  title: string;
  updatedAt: string;
}

interface SidebarProps {
  conversations: ConversationItem[];
  conversationsLoaded?: boolean;
  onNewChat: () => void;
  onDelete: (id: string) => void;
  onRename: (id: string, title: string) => void;
  onClose?: () => void;
  /** Si false, pas de poignée (ex. drawer mobile). */
  resizable?: boolean;
}

const SPACES = [
  { href: "/chat/new", label: "Chat", match: (p: string) => p.startsWith("/chat") },
  { href: "/mail", label: "Mail", match: (p: string) => p.startsWith("/mail") },
  { href: "/files", label: "Files", match: (p: string) => p.startsWith("/files") },
] as const;

export function Sidebar({
  conversations,
  conversationsLoaded = true,
  onNewChat,
  onDelete,
  onRename,
  onClose,
  resizable = true,
}: SidebarProps) {
  const pathname = usePathname();
  const [editingId, setEditingId] = useState<string | null>(null);
  const [draftTitle, setDraftTitle] = useState("");
  const [menuConv, setMenuConv] = useState<ConversationItem | null>(null);
  const editInputRef = useRef<HTMLInputElement>(null);
  const { width, setWidth, min, max } = useResizableWidth({
    storageKey: "ui.chatSidebarWidth",
    defaultWidth: 256,
    min: 220,
    max: 420,
  });

  useEffect(() => {
    if (editingId) {
      editInputRef.current?.focus();
      editInputRef.current?.select();
    }
  }, [editingId]);

  const startRename = (id: string, current: string) => {
    setEditingId(id);
    setDraftTitle(current);
  };

  const cancelRename = () => {
    setEditingId(null);
    setDraftTitle("");
  };

  const commitRename = (id: string) => {
    const title = draftTitle.trim();
    if (title) onRename(id, title);
    cancelRename();
  };

  const handleDelete = (id: string) => {
    onDelete(id);
  };

  return (
    <div className={cn("flex h-full", !resizable && "w-[var(--sidebar-width)]")}>
      <aside
        className={cn(
          "glass-sidebar flex h-full min-w-0 flex-1 flex-col overflow-hidden",
          !resizable && "w-full"
        )}
        style={resizable ? { width, flex: "none" } : undefined}
      >
        {/* Brand */}
        <div className="flex items-center gap-3 px-4 pb-3 pt-4">
          <div
            className="flex h-5 w-5 shrink-0 items-center justify-center"
            aria-hidden
          >
            <span className="block h-4 w-[3px] rounded-full bg-accent" />
          </div>
          <h1 className="flex-1 text-[15px] font-semibold tracking-[-0.02em] text-foreground">
            Chatbot
          </h1>
          <Link
            href="/settings"
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-[var(--radius-md)] text-muted transition-colors hover:bg-surface-hover hover:text-foreground"
            aria-label="Paramètres"
          >
            <Settings className="h-4 w-4" strokeWidth={1.75} />
          </Link>
        </div>

        {/* Product nav */}
        <nav aria-label="Espaces" className="px-2 pb-2">
          <ul className="space-y-0.5">
            {SPACES.map((space) => {
              const active = space.match(pathname);
              return (
                <li key={space.href}>
                  <Link
                    href={space.href}
                    onClick={onClose}
                    className={cn(
                      "flex h-8 items-center rounded-[var(--radius-md)] px-2.5 text-[13px] transition-colors",
                      active
                        ? "bg-white/[0.08] font-semibold text-foreground"
                        : "text-muted hover:bg-white/[0.04] hover:text-foreground"
                    )}
                  >
                    {space.label}
                  </Link>
                </li>
              );
            })}
          </ul>
        </nav>

        <div className="mx-4 border-t border-border" />

        {/* New chat */}
        <div className="px-2 py-2">
          <button
            type="button"
            onClick={() => {
              onNewChat();
              onClose?.();
            }}
            className="flex h-8 w-full items-center gap-2 rounded-[var(--radius-md)] px-2.5 text-[13px] font-medium text-accent transition-colors hover:bg-accent-subtle"
          >
            <Plus className="h-3.5 w-3.5" strokeWidth={2.25} />
            Nouvelle conversation
          </button>
        </div>

        {/* Conversations */}
        <div className="px-4 pb-1.5 pt-1">
          <p className="text-[10px] font-medium uppercase tracking-[0.08em] text-muted-foreground">
            Conversations
          </p>
        </div>

        <nav className="flex-1 overflow-y-auto px-2 pb-4" aria-label="Conversations">
          {!conversationsLoaded && conversations.length === 0 && (
            <p className="px-2.5 py-5 text-[12px] text-muted-foreground">
              Chargement…
            </p>
          )}
          {conversationsLoaded && conversations.length === 0 && (
            <p className="px-2.5 py-5 text-[12px] text-muted-foreground">
              Aucune conversation
            </p>
          )}
          {conversations.map((conv) => {
            const active = pathname === `/chat/${conv.id}`;
            const isEditing = editingId === conv.id;

            return (
              <div
                key={conv.id}
                className={cn(
                  "group relative mb-px flex items-center rounded-[var(--radius-md)] transition-colors",
                  active
                    ? "bg-white/[0.08]"
                    : "hover:bg-white/[0.04]"
                )}
              >
                {isEditing ? (
                  <input
                    ref={editInputRef}
                    value={draftTitle}
                    onChange={(e) => setDraftTitle(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        commitRename(conv.id);
                      } else if (e.key === "Escape") {
                        e.preventDefault();
                        cancelRename();
                      }
                    }}
                    onBlur={() => commitRename(conv.id)}
                    className="min-w-0 flex-1 rounded-[var(--radius-sm)] border border-border-subtle bg-background px-2.5 py-1.5 text-[13px] outline-none focus:outline-none focus-visible:outline-none"
                    aria-label="Renommer la conversation"
                  />
                ) : (
                  <Link
                    href={`/chat/${conv.id}`}
                    onClick={onClose}
                    onMouseEnter={() => {
                      void import("@/lib/client/conversation-messages-cache").then(
                        ({ prefetchConversationMessages }) =>
                          prefetchConversationMessages(conv.id)
                      );
                    }}
                    onFocus={() => {
                      void import("@/lib/client/conversation-messages-cache").then(
                        ({ prefetchConversationMessages }) =>
                          prefetchConversationMessages(conv.id)
                      );
                    }}
                    className={cn(
                      "min-w-0 flex-1 truncate px-2.5 py-1.5 pr-2 text-[13px]",
                      active ? "font-semibold text-foreground" : "text-muted"
                    )}
                  >
                    {conv.title}
                  </Link>
                )}
                {!isEditing && (
                  <>
                    {/* Mobile: un seul overflow */}
                    <button
                      type="button"
                      className="flex h-8 w-8 shrink-0 items-center justify-center rounded-[var(--radius-sm)] text-muted-foreground hover:bg-surface-active hover:text-foreground md:hidden"
                      aria-label="Actions de la conversation"
                      onClick={(e) => {
                        e.preventDefault();
                        e.stopPropagation();
                        setMenuConv(conv);
                      }}
                    >
                      <MoreHorizontal className="h-4 w-4" />
                    </button>

                    {/* Desktop: hover-reveal */}
                    <div
                      className={cn(
                        "hidden shrink-0 items-center pr-0.5 md:flex",
                        "md:absolute md:inset-y-0 md:right-0 md:bg-gradient-to-l md:from-60% md:to-transparent md:pl-6",
                        active
                          ? "md:from-surface-active"
                          : "md:group-hover:from-surface-hover md:from-sidebar",
                        "md:pointer-events-none md:opacity-0 md:transition-opacity md:group-hover:pointer-events-auto md:group-hover:opacity-100 md:group-focus-within:pointer-events-auto md:group-focus-within:opacity-100"
                      )}
                    >
                      <a
                        href={`/api/conversations/${conv.id}/export?format=md`}
                        className="flex h-7 w-7 items-center justify-center rounded-[var(--radius-sm)] text-muted-foreground hover:bg-surface-active hover:text-foreground"
                        title="Exporter MD"
                        aria-label="Exporter en Markdown"
                        onClick={(e) => e.stopPropagation()}
                      >
                        <Download className="h-3.5 w-3.5" />
                      </a>
                      <IconButton
                        size="sm"
                        label="Renommer"
                        onClick={(e) => {
                          e.preventDefault();
                          e.stopPropagation();
                          startRename(conv.id, conv.title);
                        }}
                        className="h-7 w-7 max-md:h-7 max-md:w-7"
                      >
                        <Pencil className="h-3.5 w-3.5" />
                      </IconButton>
                      <IconButton
                        size="sm"
                        label="Supprimer"
                        onClick={(e) => {
                          e.preventDefault();
                          e.stopPropagation();
                          handleDelete(conv.id);
                        }}
                        className="h-7 w-7 max-md:h-7 max-md:w-7"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </IconButton>
                    </div>
                  </>
                )}
              </div>
            );
          })}
        </nav>
      </aside>
      {resizable && (
        <PanelResizeHandle
          width={width}
          onWidthChange={setWidth}
          min={min}
          max={max}
          placement="after"
          label="Redimensionner la barre latérale"
          showFrom="md"
        />
      )}

      <MobileBottomSheet
        open={Boolean(menuConv)}
        onClose={() => setMenuConv(null)}
        title={menuConv?.title ?? "Conversation"}
        description="Actions"
      >
        {menuConv && (
          <ul className="space-y-0.5 p-1">
            <li>
              <MobileSheetAction
                label="Exporter Markdown"
                icon={<Download className="h-4 w-4" />}
                onClick={() => {
                  window.location.href = `/api/conversations/${menuConv.id}/export?format=md`;
                  setMenuConv(null);
                }}
              />
            </li>
            <li>
              <MobileSheetAction
                label="Renommer"
                icon={<Pencil className="h-4 w-4" />}
                onClick={() => {
                  startRename(menuConv.id, menuConv.title);
                  setMenuConv(null);
                }}
              />
            </li>
            <li>
              <MobileSheetAction
                label="Supprimer"
                icon={<Trash2 className="h-4 w-4" />}
                destructive
                onClick={() => {
                  handleDelete(menuConv.id);
                  setMenuConv(null);
                }}
              />
            </li>
          </ul>
        )}
      </MobileBottomSheet>
    </div>
  );
}
