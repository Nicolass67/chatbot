import { getEnv } from "@/lib/config/env";
import { getSearxngUrl } from "./provider-factory";

export type SearxngHealthStatus =
  | "connected"
  | "starting"
  | "unavailable"
  | "disabled";

export interface SearxngHealthResult {
  status: SearxngHealthStatus;
  url: string;
  message?: string;
  checkedAt: string;
  httpStatus?: number;
  resultCount?: number;
}

export interface SearxngHealthOptions {
  baseUrl?: string;
  timeoutMs?: number;
  signal?: AbortSignal;
}

const DEFAULT_HEALTH_TIMEOUT_MS = 8000;

/** Requête légère — n'interroge que Wikipedia (~30 ms), pas DuckDuckGo (~25 s). */
export function buildSearxngHealthCheckUrl(baseUrl: string): URL {
  const url = new URL(`${baseUrl.replace(/\/$/, "")}/search`);
  url.searchParams.set("q", "test");
  url.searchParams.set("format", "json");
  url.searchParams.set("engines", "wikipedia");
  return url;
}

function classifyHttpHealth(
  httpStatus: number
): SearxngHealthStatus | null {
  if (httpStatus >= 502 && httpStatus <= 504) return "starting";
  return null;
}

export async function checkSearxngHealth(
  options: SearxngHealthOptions = {}
): Promise<SearxngHealthResult> {
  const env = getEnv();
  const checkedAt = new Date().toISOString();
  const baseUrl = (options.baseUrl ?? getSearxngUrl()).replace(/\/$/, "");

  if (!env.WEB_SEARCH_ENABLED) {
    return {
      status: "disabled",
      url: baseUrl,
      message: "Recherche Web désactivée",
      checkedAt,
    };
  }

  const timeoutMs = options.timeoutMs ?? DEFAULT_HEALTH_TIMEOUT_MS;
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  if (options.signal) {
    options.signal.addEventListener("abort", () => controller.abort(), {
      once: true,
    });
  }

  try {
    const url = buildSearxngHealthCheckUrl(baseUrl);

    const response = await fetch(url.toString(), {
      method: "GET",
      headers: { Accept: "application/json" },
      signal: controller.signal,
    });

    const starting = classifyHttpHealth(response.status);
    if (starting) {
      return {
        status: starting,
        url: baseUrl,
        message: `SearXNG répond HTTP ${response.status} — démarrage en cours`,
        checkedAt,
        httpStatus: response.status,
      };
    }

    if (!response.ok) {
      return {
        status: "unavailable",
        url: baseUrl,
        message: `SearXNG HTTP ${response.status}`,
        checkedAt,
        httpStatus: response.status,
      };
    }

    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.includes("application/json")) {
      return {
        status: "unavailable",
        url: baseUrl,
        message:
          "SearXNG n'a pas renvoyé de JSON — vérifiez search.formats dans settings.yml",
        checkedAt,
        httpStatus: response.status,
      };
    }

    let data: { results?: unknown[] };
    try {
      data = (await response.json()) as { results?: unknown[] };
    } catch {
      return {
        status: "unavailable",
        url: baseUrl,
        message: "Réponse JSON SearXNG invalide",
        checkedAt,
        httpStatus: response.status,
      };
    }

    if (!Array.isArray(data.results)) {
      return {
        status: "unavailable",
        url: baseUrl,
        message: "Réponse SearXNG sans tableau results",
        checkedAt,
        httpStatus: response.status,
      };
    }

    const unresponsive = (
      data as { unresponsive_engines?: unknown[] }
    ).unresponsive_engines;

    if (data.results.length === 0) {
      if (unresponsive && unresponsive.length > 0) {
        return {
          status: "starting",
          url: baseUrl,
          message:
            "SearXNG répond mais les moteurs sont suspendus — réessayez dans quelques secondes",
          checkedAt,
          httpStatus: response.status,
          resultCount: 0,
        };
      }
      return {
        status: "starting",
        url: baseUrl,
        message: "SearXNG répond mais la requête test n'a renvoyé aucun résultat",
        checkedAt,
        httpStatus: response.status,
        resultCount: 0,
      };
    }

    return {
      status: "connected",
      url: baseUrl,
      message: "SearXNG connecté",
      checkedAt,
      httpStatus: response.status,
      resultCount: data.results.length,
    };
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      return {
        status: "starting",
        url: baseUrl,
        message:
          "SearXNG ne répond pas encore (timeout) — démarrage ou moteurs lents",
        checkedAt,
      };
    }

    const msg = error instanceof Error ? error.message : String(error);
    const isRefused =
      msg.includes("ECONNREFUSED") ||
      msg.includes("fetch failed") ||
      msg.includes("ECONNRESET");

    return {
      status: isRefused ? "unavailable" : "unavailable",
      url: baseUrl,
      message: isRefused
        ? "SearXNG indisponible — instance non joignable"
        : msg,
      checkedAt,
    };
  } finally {
    clearTimeout(timeoutId);
  }
}

let healthCache: { result: SearxngHealthResult; expiresAt: number } | null = null;

export function clearSearxngHealthCache(): void {
  healthCache = null;
}

export async function getCachedSearxngHealth(
  options: SearxngHealthOptions = {}
): Promise<SearxngHealthResult> {
  const ttlMs = 3000;
  if (!options.baseUrl && !options.timeoutMs && !options.signal) {
    if (healthCache && Date.now() < healthCache.expiresAt) {
      return healthCache.result;
    }
  }

  const result = await checkSearxngHealth(options);
  if (!options.baseUrl && !options.timeoutMs && !options.signal) {
    healthCache = { result, expiresAt: Date.now() + ttlMs };
  }
  return result;
}

export interface WaitForSearxngOptions {
  baseUrl?: string;
  timeoutMs?: number;
  intervalMs?: number;
  checkTimeoutMs?: number;
  onProgress?: (elapsedMs: number, last: SearxngHealthResult) => void;
}

/** Attente bornée — utilisée par les scripts de bootstrap, pas par Next.js. */
export async function waitForSearxngHealth(
  options: WaitForSearxngOptions = {}
): Promise<SearxngHealthResult> {
  const timeoutMs = options.timeoutMs ?? 60_000;
  const intervalMs = options.intervalMs ?? 2000;
  const started = Date.now();
  let last = await checkSearxngHealth({
    baseUrl: options.baseUrl,
    timeoutMs: options.checkTimeoutMs ?? 3000,
  });

  if (last.status === "connected" && (last.resultCount ?? 0) > 0) return last;

  while (Date.now() - started < timeoutMs) {
    await new Promise((r) => setTimeout(r, intervalMs));
    last = await checkSearxngHealth({
      baseUrl: options.baseUrl,
      timeoutMs: options.checkTimeoutMs ?? 15000,
    });
    options.onProgress?.(Date.now() - started, last);
    if (last.status === "connected" && (last.resultCount ?? 0) > 0) {
      return last;
    }
  }

  return last;
}
