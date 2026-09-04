"use client";

import { cn } from "@/lib/utils/cn";
import type { MailMessageSummary } from "@/lib/mail/mail-client";

interface MailListProps {
  messages: MailMessageSummary[];
  selectedThreadId?: string;
  hiddenMessageIds?: Set<string>;
  loading?: boolean;
  onSelectThread?: (threadId: string, messageId: string) => void;
}

function formatFrom(from: MailMessageSummary["from"]): string {
  return from.name?.trim() || from.email;
}

function formatDate(date: string): string {
  const d = new Date(date);
  if (Number.isNaN(d.getTime())) return date;
  const now = new Date();
  const sameDay =
    d.getDate() === now.getDate() &&
    d.getMonth() === now.getMonth() &&
    d.getFullYear() === now.getFullYear();

  if (sameDay) {
    return d.toLocaleTimeString("fr-FR", {
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  return d.toLocaleDateString("fr-FR", {
    day: "numeric",
    month: "short",
  });
}

export function MailList({
  messages,
  selectedThreadId,
  hiddenMessageIds,
  loading,
  onSelectThread,
}: MailListProps) {
  if (loading) {
    return (
      <div className="divide-y divide-border-subtle">
        {Array.from({ length: 8 }).map((_, index) => (
          <div
            key={index}
            className="animate-pulse px-3 py-3"
          >
            <div className="mb-2 h-2.5 w-1/4 rounded-sm bg-border-subtle" />
            <div className="mb-1.5 h-2.5 w-2/3 rounded-sm bg-border-subtle" />
            <div className="h-2.5 w-full rounded-sm bg-border-subtle/70" />
          </div>
        ))}
      </div>
    );
  }

  const visible = messages.filter((m) => !hiddenMessageIds?.has(m.id));

  if (visible.length === 0) {
    return (
      <p className="px-4 py-12 text-center text-sm text-muted-foreground">
        Aucun message dans cette catégorie
      </p>
    );
  }

  return (
    <ul className="divide-y divide-border-subtle lg:divide-y">
      {visible.map((message) => {
        const active = message.threadId === selectedThreadId;
        return (
          <li key={message.id}>
            <button
              type="button"
              onClick={() => onSelectThread?.(message.threadId, message.id)}
              className={cn(
                "relative block w-full touch-manipulation text-left transition-colors",
                "min-h-[4.75rem] px-4 py-3.5 active:bg-surface-hover lg:min-h-0 lg:py-3 lg:hover:bg-surface-hover",
                active && "bg-surface-hover lg:bg-surface-hover",
                active &&
                  "before:absolute before:inset-y-0 before:left-0 before:w-1 before:bg-accent lg:before:hidden"
              )}
            >
              <div className="flex items-start gap-3">
                <div
                  className={cn(
                    "mt-1.5 h-2.5 w-2.5 shrink-0 rounded-full",
                    message.isUnread ? "bg-accent" : "bg-transparent"
                  )}
                  aria-hidden
                />
                <div className="min-w-0 flex-1">
                  <div className="mb-0.5 flex items-baseline justify-between gap-2">
                    <span
                      className={cn(
                        "truncate text-[15px] text-foreground lg:text-sm",
                        message.isUnread && "font-semibold"
                      )}
                    >
                      {formatFrom(message.from)}
                    </span>
                    <span className="shrink-0 text-[11px] text-muted-foreground">
                      {formatDate(message.date)}
                    </span>
                  </div>
                  <p
                    className={cn(
                      "truncate text-sm text-foreground",
                      message.isUnread && "font-medium"
                    )}
                  >
                    {message.subject}
                  </p>
                  <p className="mt-0.5 line-clamp-2 text-xs leading-relaxed text-muted-foreground lg:truncate lg:whitespace-nowrap">
                    {message.snippet}
                  </p>
                </div>
              </div>
            </button>
          </li>
        );
      })}
    </ul>
  );
}
