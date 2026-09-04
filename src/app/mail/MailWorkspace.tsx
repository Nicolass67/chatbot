"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { MailLayout } from "@/components/mail/MailLayout";
import { MailList } from "@/components/mail/MailList";
import { MailSearchBar } from "@/components/mail/MailSearchBar";
import { MailOAuthBanner } from "@/components/mail/MailOAuthBanner";
import { MailCategoryTabs } from "@/components/mail/MailCategoryTabs";
import {
  MailAssistantPanel,
  MailThreadPanel,
} from "@/components/mail/MailAssistantPanel";
import {
  MailMobileListHeader,
  MailReadingModal,
} from "@/components/mail/MailMobileShell";
import { MailAssistantFab } from "@/components/mail/MailAssistantFab";
import { useMediaQuery } from "@/hooks/useMediaQuery";
import {
  fetchMailMessages,
  fetchMailThread,
  fetchOAuthAccounts,
  markMailMessageRead,
  type MailMessageSummary,
  type MailThread,
  type OAuthAccountPublic,
} from "@/lib/mail/mail-client";
import {
  parseMailCategory,
  type MailCategory,
} from "@/lib/mail/categories";

function buildMailUrl(params: {
  category?: MailCategory;
  q?: string;
  thread?: string | null;
  message?: string | null;
}): string {
  const search = new URLSearchParams();
  if (params.q?.trim()) {
    search.set("q", params.q.trim());
  } else if (params.category && params.category !== "primary") {
    search.set("category", params.category);
  }
  if (params.thread) search.set("thread", params.thread);
  if (params.message) search.set("message", params.message);
  const qs = search.toString();
  return qs ? `/mail?${qs}` : "/mail";
}

export default function MailWorkspace() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const isDesktop = useMediaQuery("(min-width: 1024px)");

  const q = searchParams.get("q") ?? "";
  const category = q
    ? ("primary" as MailCategory)
    : parseMailCategory(searchParams.get("category"));
  const threadIdFromUrl = searchParams.get("thread");
  const messageFromUrl = searchParams.get("message");

  const [accounts, setAccounts] = useState<OAuthAccountPublic[]>([]);
  const [messages, setMessages] = useState<MailMessageSummary[]>([]);
  const [thread, setThread] = useState<MailThread | null>(null);
  const [selectedThreadId, setSelectedThreadId] = useState<string | null>(
    threadIdFromUrl
  );
  const [selectedMessageId, setSelectedMessageId] = useState<string | null>(
    messageFromUrl
  );
  const [hiddenMessageIds, setHiddenMessageIds] = useState<Set<string>>(
    () => new Set()
  );
  const [searchDraft, setSearchDraft] = useState(q);
  const [listLoading, setListLoading] = useState(true);
  const [threadLoading, setThreadLoading] = useState(false);
  const [threadCollapsed, setThreadCollapsed] = useState(false);
  const [assistantOpen, setAssistantOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const resolvedSelectedMessageId = useMemo(() => {
    if (selectedMessageId) return selectedMessageId;
    const last = thread?.messages[thread.messages.length - 1];
    return last?.id ?? null;
  }, [selectedMessageId, thread]);

  const loadAccounts = useCallback(async () => {
    const oauth = await fetchOAuthAccounts();
    setAccounts(oauth.accounts);
    return oauth;
  }, []);

  const loadMessages = useCallback(async () => {
    setListLoading(true);
    setError(null);
    try {
      const oauth = await loadAccounts();
      if (!oauth.configured || oauth.accounts.length === 0) {
        setMessages([]);
        return;
      }
      const msgs = await fetchMailMessages(
        q
          ? { q }
          : category === "unread"
            ? { label: "UNREAD" }
            : category === "inbox"
              ? { label: "INBOX" }
              : { category }
      );
      setMessages(msgs);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur de chargement");
    } finally {
      setListLoading(false);
    }
  }, [q, category, loadAccounts]);

  const loadThread = useCallback(async (threadId: string) => {
    setThreadLoading(true);
    setError(null);
    try {
      const threadData = await fetchMailThread(threadId);
      setThread(threadData);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Erreur de chargement du fil"
      );
      setThread(null);
    } finally {
      setThreadLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadMessages();
  }, [loadMessages]);

  useEffect(() => {
    setSelectedThreadId(threadIdFromUrl);
    setSelectedMessageId(messageFromUrl);
    if (threadIdFromUrl) {
      void loadThread(threadIdFromUrl);
    } else {
      setThread(null);
    }
  }, [threadIdFromUrl, messageFromUrl, loadThread]);

  const selectThread = (threadId: string, messageId?: string) => {
    setSelectedThreadId(threadId);
    setSelectedMessageId(messageId ?? null);
    setThreadCollapsed(false);
    void loadThread(threadId);

    if (messageId) {
      setMessages((prev) =>
        prev.map((m) =>
          m.id === messageId || m.threadId === threadId
            ? { ...m, isUnread: false }
            : m
        )
      );
      void markMailMessageRead(messageId).catch(() => undefined);
    }

    router.replace(
      buildMailUrl({
        category: q ? undefined : category,
        q: q || undefined,
        thread: threadId,
        message: messageId ?? null,
      }),
      { scroll: false }
    );
  };

  const closeThread = () => {
    // Ne ferme PAS l'assistant — il reste au-dessus / indépendant
    setSelectedThreadId(null);
    setSelectedMessageId(null);
    setThread(null);
    router.replace(buildMailUrl({ category, q: q || undefined }), {
      scroll: false,
    });
  };

  const handleCategoryChange = (next: MailCategory) => {
    setSelectedThreadId(null);
    setSelectedMessageId(null);
    setThread(null);
    router.replace(buildMailUrl({ category: next }), { scroll: false });
  };

  const handleSearch = () => {
    const trimmed = searchDraft.trim();
    setSelectedThreadId(null);
    setSelectedMessageId(null);
    setThread(null);
    router.replace(
      trimmed ? `/mail?q=${encodeURIComponent(trimmed)}` : "/mail",
      { scroll: false }
    );
  };

  const handleTrashConfirmed = (messageId: string) => {
    setHiddenMessageIds((prev) => new Set(prev).add(messageId));
    if (thread) {
      const remaining = thread.messages.filter((m) => m.id !== messageId);
      setThread({ ...thread, messages: remaining });
      if (remaining.length === 0) {
        closeThread();
      }
    }
    void loadMessages();
  };

  const handleTrashFailed = () => {
    if (selectedThreadId) void loadThread(selectedThreadId);
  };

  const listPanel = (
    <div className="flex h-full flex-col">
      <div className="sticky top-0 z-10 border-b border-border-subtle bg-surface p-3 lg:static">
        <MailSearchBar
          value={searchDraft}
          onChange={setSearchDraft}
          onSubmit={handleSearch}
          disabled={listLoading}
        />
      </div>
      {!q && (
        <MailCategoryTabs
          active={category}
          onChange={handleCategoryChange}
          disabled={listLoading}
        />
      )}
      {error && !selectedThreadId && (
        <p className="px-4 py-2 text-sm text-red-500" role="alert">
          {error}
        </p>
      )}
      <div className="flex-1 overflow-y-auto overscroll-contain pb-28 lg:pb-0">
        <MailList
          messages={messages}
          selectedThreadId={selectedThreadId ?? undefined}
          hiddenMessageIds={hiddenMessageIds}
          loading={listLoading}
          onSelectThread={selectThread}
        />
      </div>
    </div>
  );

  const assistantProps = {
    thread,
    selectedMessageId: resolvedSelectedMessageId,
    accountEmail: accounts[0]?.accountEmail,
    onTrashConfirmed: handleTrashConfirmed,
    onTrashFailed: handleTrashFailed,
  };

  return (
    <MailLayout
      mobileHideList={false}
      mobileHideDetail
      mobileHeader={
        <MailMobileListHeader
          scope={
            category === "unread"
              ? "unread"
              : category === "inbox"
                ? "inbox"
                : null
          }
          onScopeChange={(scope) => handleCategoryChange(scope)}
          disabled={listLoading}
        />
      }
      banner={
        <MailOAuthBanner
          accounts={accounts}
          className="mx-3 mt-2 lg:mx-4 lg:mt-3"
        />
      }
      overlay={
        <>
          {!isDesktop ? (
            <MailReadingModal
              open={!!selectedThreadId}
              title={thread?.subject}
              loading={threadLoading}
              onClose={closeThread}
            >
              <MailThreadPanel
                thread={thread}
                selectedMessageId={resolvedSelectedMessageId}
                loading={threadLoading}
                collapsed={false}
                onToggleCollapse={() => undefined}
                compactHeader
              />
            </MailReadingModal>
          ) : null}

          <MailAssistantFab
            open={assistantOpen}
            onOpen={() => setAssistantOpen(true)}
            onClose={() => setAssistantOpen(false)}
          >
            <MailAssistantPanel {...assistantProps} fullScreen compact />
          </MailAssistantFab>
        </>
      }
      sidebar={listPanel}
    >
      <div className="hidden h-full min-h-0 w-full min-w-0 flex-1 lg:flex">
        <MailThreadPanel
          thread={thread}
          selectedMessageId={resolvedSelectedMessageId}
          loading={threadLoading}
          collapsed={threadCollapsed}
          onToggleCollapse={() => setThreadCollapsed((v) => !v)}
        />
      </div>
    </MailLayout>
  );
}
