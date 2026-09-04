/**
 * Module-level cache so switching conversations can paint instantly
 * even when ChatView remounts on route change.
 */

type CachedMessages = {
  messages: unknown[];
  at: number;
};

const cache = new Map<string, CachedMessages>();
const inflight = new Map<string, Promise<unknown[]>>();
const TTL_MS = 60_000;

export function peekCachedMessages<T>(conversationId: string): T[] | null {
  const hit = cache.get(conversationId);
  if (!hit) return null;
  if (Date.now() - hit.at > TTL_MS) {
    cache.delete(conversationId);
    return null;
  }
  return hit.messages as T[];
}

export function putCachedMessages(conversationId: string, messages: unknown[]) {
  cache.set(conversationId, { messages, at: Date.now() });
}

export function invalidateCachedMessages(conversationId?: string) {
  if (!conversationId) {
    cache.clear();
    return;
  }
  cache.delete(conversationId);
}

/** Prefetch + cache messages for a conversation (sidebar hover / warm). */
export function prefetchConversationMessages(
  conversationId: string
): Promise<unknown[]> {
  if (conversationId === "new") return Promise.resolve([]);
  const existing = peekCachedMessages(conversationId);
  if (existing) return Promise.resolve(existing);

  let pending = inflight.get(conversationId);
  if (!pending) {
    pending = fetch(`/api/conversations/${conversationId}/messages`)
      .then(async (res) => {
        if (!res.ok) return [];
        const data = (await res.json()) as { messages?: unknown[] };
        const msgs = data.messages ?? [];
        putCachedMessages(conversationId, msgs);
        return msgs;
      })
      .catch(() => [] as unknown[])
      .finally(() => {
        inflight.delete(conversationId);
      });
    inflight.set(conversationId, pending);
  }
  return pending;
}
