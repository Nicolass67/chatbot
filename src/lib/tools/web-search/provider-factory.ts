import { getEnv } from "@/lib/config/env";
import { BraveSearchProvider } from "./brave-provider";
import { CompositeWebSearchProvider } from "./composite-provider";
import { DuckDuckGoProvider } from "./provider";
import { SearxngProvider } from "./searxng-provider";
import type { WebSearchProvider } from "./web-search-types";

export function getSearxngUrl(): string {
  return getEnv().SEARXNG_URL ?? "http://localhost:8080";
}

export function getPrimaryProviderLabel(): string {
  const env = getEnv();
  if (env.WEB_SEARCH_PROVIDER === "auto") return "SearXNG";
  if (env.WEB_SEARCH_PROVIDER === "searxng") return "SearXNG";
  if (env.WEB_SEARCH_PROVIDER === "brave") return "Brave";
  if (env.WEB_SEARCH_PROVIDER === "duckduckgo") return "DuckDuckGo";
  return env.WEB_SEARCH_PROVIDER;
}

export function createWebSearchProvider(): WebSearchProvider {
  const env = getEnv();

  switch (env.WEB_SEARCH_PROVIDER) {
    case "duckduckgo":
      return new DuckDuckGoProvider();
    case "brave":
      if (!env.BRAVE_SEARCH_API_KEY) {
        throw new Error(
          "WEB_SEARCH_PROVIDER=brave nécessite BRAVE_SEARCH_API_KEY dans .env.local"
        );
      }
      return new BraveSearchProvider(env.BRAVE_SEARCH_API_KEY);
    case "searxng":
      return new SearxngProvider(getSearxngUrl());
    case "auto":
    default:
      return createAutoProvider();
  }
}

function createAutoProvider(): WebSearchProvider {
  const env = getEnv();
  const chain: WebSearchProvider[] = [new SearxngProvider(getSearxngUrl())];

  if (env.BRAVE_SEARCH_API_KEY) {
    chain.push(new BraveSearchProvider(env.BRAVE_SEARCH_API_KEY));
  }

  return new CompositeWebSearchProvider(chain);
}
