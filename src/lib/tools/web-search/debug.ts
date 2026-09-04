import type { WebSearchStatus } from "../types";

export interface WebSearchDebugInfo {
  query: string;
  status: WebSearchStatus;
  provider?: string;
  httpStatus?: number;
  resultCount: number;
  parsedResultCount: number;
  usableResultCount: number;
  error?: string;
  deduplicated?: boolean;
}

export function logWebSearchDebug(info: WebSearchDebugInfo): void {
  if (process.env.NODE_ENV === "production") return;
  console.log(
    [
      "[WEB SEARCH]",
      `query: ${info.query}`,
      `provider: ${info.provider ?? "—"}`,
      `status: ${info.status}`,
      `httpStatus: ${info.httpStatus ?? "—"}`,
      `resultCount: ${info.resultCount}`,
      `parsedResultCount: ${info.parsedResultCount}`,
      `usableResultCount: ${info.usableResultCount}`,
      `error: ${info.error ?? "—"}`,
      info.deduplicated ? "deduplicated: true" : null,
    ]
      .filter(Boolean)
      .join("\n")
  );
}
