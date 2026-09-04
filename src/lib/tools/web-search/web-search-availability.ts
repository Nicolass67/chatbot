import { getEnv } from "@/lib/config/env";
import {
  clearSearxngHealthCache,
  getCachedSearxngHealth,
  waitForSearxngHealth,
  type SearxngHealthResult,
} from "./searxng-health";

export interface WebSearchAvailability {
  available: boolean;
  reason?: string;
  provider: string;
  searxng: SearxngHealthResult;
}

export interface WebSearchAvailabilityOptions {
  /** Attente si SearXNG est en démarrage (moteurs suspendus). 0 = pas d'attente. */
  waitIfStartingMs?: number;
}

const DEFAULT_STARTUP_WAIT_MS = 45_000;

export function usesSearxngAsPrimary(): boolean {
  const provider = getEnv().WEB_SEARCH_PROVIDER;
  return provider === "searxng" || provider === "auto";
}

function canFallbackWithoutSearxng(env: ReturnType<typeof getEnv>): boolean {
  return (
    env.WEB_SEARCH_PROVIDER === "brave" ||
    env.WEB_SEARCH_PROVIDER === "duckduckgo" ||
    (env.WEB_SEARCH_PROVIDER === "auto" && Boolean(env.BRAVE_SEARCH_API_KEY))
  );
}

function buildUnavailableReason(searxng: SearxngHealthResult): string {
  return searxng.status === "starting"
    ? "SearXNG démarrage — recherche Web temporairement indisponible"
    : "SearXNG indisponible — impossible de vérifier les données actuelles";
}

async function resolveSearxngHealth(
  options: WebSearchAvailabilityOptions
): Promise<SearxngHealthResult> {
  const env = getEnv();
  const waitMs = options.waitIfStartingMs ?? DEFAULT_STARTUP_WAIT_MS;
  let searxng = await getCachedSearxngHealth();

  if (
    waitMs > 0 &&
    env.WEB_SEARCH_ENABLED &&
    !canFallbackWithoutSearxng(env) &&
    searxng.status === "starting"
  ) {
    clearSearxngHealthCache();
    searxng = await waitForSearxngHealth({
      timeoutMs: waitMs,
      intervalMs: 2000,
      checkTimeoutMs: 8000,
    });
    clearSearxngHealthCache();
  }

  return searxng;
}

/** Vérifie si une recherche Web fraîche peut être tentée (sans lancer Docker). */
export async function evaluateWebSearchAvailability(
  options: WebSearchAvailabilityOptions = {}
): Promise<WebSearchAvailability> {
  const env = getEnv();
  const searxng = await resolveSearxngHealth(options);

  if (!env.WEB_SEARCH_ENABLED) {
    return {
      available: false,
      reason: "Recherche Web désactivée",
      provider: env.WEB_SEARCH_PROVIDER,
      searxng,
    };
  }

  if (env.WEB_SEARCH_PROVIDER === "brave") {
    if (!env.BRAVE_SEARCH_API_KEY) {
      return {
        available: false,
        reason: "BRAVE_SEARCH_API_KEY non configurée",
        provider: "brave",
        searxng,
      };
    }
    return { available: true, provider: "brave", searxng };
  }

  if (env.WEB_SEARCH_PROVIDER === "duckduckgo") {
    return { available: true, provider: "duckduckgo", searxng };
  }

  if (searxng.status === "connected") {
    return { available: true, provider: env.WEB_SEARCH_PROVIDER, searxng };
  }

  if (
    env.WEB_SEARCH_PROVIDER === "auto" &&
    env.BRAVE_SEARCH_API_KEY
  ) {
    return {
      available: true,
      provider: "auto",
      searxng,
    };
  }

  const reason = buildUnavailableReason(searxng);

  return {
    available: false,
    reason,
    provider: env.WEB_SEARCH_PROVIDER,
    searxng,
  };
}
