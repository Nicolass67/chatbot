/**
 * Client-side GET cache + in-flight dedupe for navigation-critical APIs.
 * Prevents Strict Mode double-fetch and Chat remount storms.
 */

type CacheEntry = {
  at: number;
  status: number;
  body: unknown;
};

const cache = new Map<string, CacheEntry>();
const inflight = new Map<string, Promise<CacheEntry>>();

const DEFAULT_TTL_MS = 30_000;

export function invalidateClientFetchCache(urlPrefix?: string) {
  if (!urlPrefix) {
    cache.clear();
    return;
  }
  for (const key of cache.keys()) {
    if (key.startsWith(urlPrefix)) cache.delete(key);
  }
}

export async function cachedGetJson<T>(
  url: string,
  options?: { ttlMs?: number; bust?: boolean }
): Promise<{ ok: boolean; status: number; data: T }> {
  const ttlMs = options?.ttlMs ?? DEFAULT_TTL_MS;
  if (options?.bust) cache.delete(url);

  const hit = cache.get(url);
  if (hit && Date.now() - hit.at < ttlMs) {
    return {
      ok: hit.status >= 200 && hit.status < 300,
      status: hit.status,
      data: hit.body as T,
    };
  }

  let pending = inflight.get(url);
  if (!pending) {
    pending = (async () => {
      const res = await fetch(url);
      let body: unknown = null;
      try {
        body = await res.json();
      } catch {
        body = null;
      }
      const entry: CacheEntry = {
        at: Date.now(),
        status: res.status,
        body,
      };
      if (res.ok) cache.set(url, entry);
      return entry;
    })().finally(() => {
      inflight.delete(url);
    });
    inflight.set(url, pending);
  }

  const entry = await pending;
  return {
    ok: entry.status >= 200 && entry.status < 300,
    status: entry.status,
    data: entry.body as T,
  };
}
