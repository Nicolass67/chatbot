import type { SearchResult, WebSearchStatus } from "../types";

export type { WebSearchStatus };

export interface WebSearchOptions {
  maxResults: number;
  timeoutMs: number;
  signal: AbortSignal;
}

export interface WebSearchDiagnostics {
  httpStatus?: number;
  rawCount: number;
  parsedCount: number;
  provider: string;
}

export interface WebSearchProviderResult {
  status: WebSearchStatus;
  provider: string;
  results: SearchResult[];
  error?: string;
  diagnostics: WebSearchDiagnostics;
}

export interface WebSearchProvider {
  readonly name: string;
  search(
    query: string,
    options: WebSearchOptions
  ): Promise<WebSearchProviderResult>;
}

export class WebSearchError extends Error {
  constructor(
    message: string,
    readonly status: WebSearchStatus,
    readonly provider: string,
    readonly diagnostics?: Partial<WebSearchDiagnostics>
  ) {
    super(message);
    this.name = "WebSearchError";
  }
}

export function isWebSearchFailureStatus(status: WebSearchStatus): boolean {
  return (
    status === "provider_error" ||
    status === "timeout" ||
    status === "blocked"
  );
}

export function classifyFetchError(
  error: unknown,
  provider: string
): WebSearchProviderResult {
  if (error instanceof DOMException && error.name === "AbortError") {
    return {
      status: "timeout",
      provider,
      results: [],
      error: "Délai de recherche Web dépassé",
      diagnostics: { rawCount: 0, parsedCount: 0, provider },
    };
  }
  const msg = error instanceof Error ? error.message : String(error);
  return {
    status: "provider_error",
    provider,
    results: [],
    error: msg,
    diagnostics: { rawCount: 0, parsedCount: 0, provider },
  };
}
