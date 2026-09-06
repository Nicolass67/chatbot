/**
 * Fetch léger d'une page Web pour grounding (HTML → texte).
 * Pas de headless browser — extraction texte basique, budget strict.
 */

const DEFAULT_MAX_BYTES = 500_000;
/** Budget texte page élevé pour extraction question-focused (V3). */
const DEFAULT_MAX_CHARS = 24_000;
const FETCH_TIMEOUT_MS = 12_000;

export type FetchedPage = {
  url: string;
  ok: boolean;
  title?: string;
  text?: string;
  error?: string;
  status?: number;
};


function tableToText(tableHtml: string): string {
  const rows = tableHtml.match(/<tr[\s\S]*?<\/tr>/gi) ?? [];
  const lines: string[] = [];
  for (const row of rows) {
    const cells = [...row.matchAll(/<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi)]
      .map((m) =>
        m[1]!
          .replace(/<[^>]+>/g, " ")
          .replace(/&nbsp;/g, " ")
          .replace(/\s+/g, " ")
          .trim()
      )
      .filter(Boolean);
    if (cells.length > 0) lines.push(cells.join(" | "));
  }
  return lines.join("\n");
}

function listToText(listHtml: string): string {
  const items = [...listHtml.matchAll(/<li[^>]*>([\s\S]*?)<\/li>/gi)]
    .map((m) =>
      m[1]!
        .replace(/<[^>]+>/g, " ")
        .replace(/\s+/g, " ")
        .trim()
    )
    .filter(Boolean);
  return items.map((it) => `- ${it}`).join("\n");
}

function stripHtml(html: string): { title: string; text: string } {
  const titleMatch = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  const title = titleMatch
    ? titleMatch[1].replace(/\s+/g, " ").trim().slice(0, 200)
    : "";
  let work = html;
  work = work.replace(/<table[\s\S]*?<\/table>/gi, (table) => `\n${tableToText(table)}\n`);
  work = work.replace(/<(ul|ol)[\s\S]*?<\/\1>/gi, (list) => `\n${listToText(list)}\n`);
  const text = work
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<noscript[\s\S]*?<\/noscript>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, " ")
    .replace(/<\/(p|div|h[1-6]|li|tr|br|section|article)>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/[ \t]{2,}/g, " ")
    .trim();
  return { title, text };
}

export async function fetchWebPageText(
  url: string,
  options?: {
    signal?: AbortSignal;
    maxBytes?: number;
    maxChars?: number;
    timeoutMs?: number;
  }
): Promise<FetchedPage> {
  const maxBytes = options?.maxBytes ?? DEFAULT_MAX_BYTES;
  const maxChars = options?.maxChars ?? DEFAULT_MAX_CHARS;
  const timeoutMs = options?.timeoutMs ?? FETCH_TIMEOUT_MS;

  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return { url, ok: false, error: "URL invalide" };
  }
  if (!/^https?:$/i.test(parsed.protocol)) {
    return { url, ok: false, error: "Protocole non autorisé" };
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const onOuterAbort = () => controller.abort();
  options?.signal?.addEventListener("abort", onOuterAbort);

  try {
    const res = await fetch(url, {
      method: "GET",
      redirect: "follow",
      signal: controller.signal,
      headers: {
        Accept: "text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.8",
        "User-Agent": "ChatbotLocalBot/1.0 (+local; grounding)",
      },
    });
    if (!res.ok) {
      return { url, ok: false, status: res.status, error: `HTTP ${res.status}` };
    }
    const ctype = (res.headers.get("content-type") ?? "").toLowerCase();
    if (
      ctype &&
      !ctype.includes("text/html") &&
      !ctype.includes("text/plain") &&
      !ctype.includes("xhtml")
    ) {
      return {
        url,
        ok: false,
        status: res.status,
        error: `Type non textuel: ${ctype}`,
      };
    }
    const buf = Buffer.from(await res.arrayBuffer());
    const sliced = buf.subarray(0, maxBytes).toString("utf8");
    if (ctype.includes("text/plain")) {
      return {
        url,
        ok: true,
        status: res.status,
        text: sliced.slice(0, maxChars),
      };
    }
    const { title, text } = stripHtml(sliced);
    if (!text || text.length < 40) {
      return {
        url,
        ok: false,
        status: res.status,
        title,
        error: "Contenu textuel insuffisant",
      };
    }
    return {
      url,
      ok: true,
      status: res.status,
      title,
      text: text.slice(0, maxChars),
    };
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const aborted =
      (err instanceof Error && err.name === "AbortError") ||
      options?.signal?.aborted;
    return {
      url,
      ok: false,
      error: aborted ? "Timeout/abort fetch page" : msg,
    };
  } finally {
    clearTimeout(timer);
    options?.signal?.removeEventListener("abort", onOuterAbort);
  }
}

/**
 * Enrichit les top résultats dont le snippet est insuffisant.
 */
export async function deepenSearchResults(input: {
  query: string;
  results: Array<{ title: string; url: string; snippet: string }>;
  maxPages?: number;
  signal?: AbortSignal;
  snippetInsufficient: (snippet: string, query: string) => boolean;
  onProgress?: (info: {
    phase: "fetching" | "done";
    url: string;
    title: string;
    domain?: string;
    index: number;
    total: number;
  }) => void;
}): Promise<Record<string, string>> {
  const maxPages = input.maxPages ?? 2;
  const pageContents: Record<string, string> = {};
  const candidates = input.results
    .filter((r) => input.snippetInsufficient(r.snippet, input.query))
    .slice(0, maxPages);
  const total = candidates.length;

  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i]!;
    if (input.signal?.aborted) break;
    let domain: string | undefined;
    try {
      domain = new URL(c.url).hostname.replace(/^www\./, "");
    } catch {
      domain = undefined;
    }
    input.onProgress?.({
      phase: "fetching",
      url: c.url,
      title: c.title,
      domain,
      index: i + 1,
      total,
    });
    const page = await fetchWebPageText(c.url, { signal: input.signal });
    if (page.ok && page.text) {
      pageContents[c.url] = page.text;
    }
  }

  if (total > 0) {
    const last = candidates[candidates.length - 1]!;
    let domain: string | undefined;
    try {
      domain = new URL(last.url).hostname.replace(/^www\./, "");
    } catch {
      domain = undefined;
    }
    input.onProgress?.({
      phase: "done",
      url: last.url,
      title: last.title,
      domain,
      index: total,
      total,
    });
  }

  return pageContents;
}
