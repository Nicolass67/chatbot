/**
 * Uniform API error body for Client Surface + middleware.
 * Always includes human `error` + machine `code` (forward-compatible).
 */

export const API_ERROR_CODES = [
  "AUTH_REQUIRED",
  "FORBIDDEN",
  "NOT_FOUND",
  "VALIDATION_ERROR",
  "FEATURE_DISABLED",
  "EMAIL_NOT_CONNECTED",
  "PROVIDER_ERROR",
  "AI_ERROR",
  "RATE_LIMITED",
  "INVALID_STATE",
  "EXPIRED",
  "ALREADY_USED",
  "POLICY_DENIED",
  "HASH_MISMATCH",
  "DRAFT_NOT_FOUND",
  "DRAFT_NOT_VALIDATED",
  "MESSAGE_NOT_FOUND",
  "SEND_FAILED",
  "TRASH_FAILED",
  "ABORTED",
  "INTERNAL",
] as const;

export type ApiErrorCode = (typeof API_ERROR_CODES)[number];

export type ApiErrorBody = {
  error: string;
  code: ApiErrorCode;
  details?: Record<string, unknown>;
};

const DEFAULT_STATUS: Partial<Record<ApiErrorCode, number>> = {
  AUTH_REQUIRED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  VALIDATION_ERROR: 400,
  FEATURE_DISABLED: 503,
  EMAIL_NOT_CONNECTED: 403,
  PROVIDER_ERROR: 502,
  AI_ERROR: 500,
  RATE_LIMITED: 429,
  INVALID_STATE: 409,
  EXPIRED: 410,
  ALREADY_USED: 409,
  POLICY_DENIED: 403,
  HASH_MISMATCH: 409,
  DRAFT_NOT_FOUND: 404,
  DRAFT_NOT_VALIDATED: 400,
  MESSAGE_NOT_FOUND: 404,
  SEND_FAILED: 500,
  TRASH_FAILED: 500,
  ABORTED: 499,
  INTERNAL: 500,
};

export function isApiErrorCode(value: unknown): value is ApiErrorCode {
  return (
    typeof value === "string" &&
    (API_ERROR_CODES as readonly string[]).includes(value)
  );
}

export function assertApiErrorShape(body: unknown): asserts body is ApiErrorBody {
  if (!body || typeof body !== "object") {
    throw new Error("API error body must be an object");
  }
  const record = body as Record<string, unknown>;
  if (typeof record.error !== "string" || !record.error.trim()) {
    throw new Error("API error body requires non-empty string `error`");
  }
  if (!isApiErrorCode(record.code)) {
    throw new Error(`API error body has invalid code: ${String(record.code)}`);
  }
}

/** Map ActionError / legacy string codes into the shared catalogue when possible. */
export function normalizeApiErrorCode(code: string): ApiErrorCode {
  if (isApiErrorCode(code)) return code;
  return "INTERNAL";
}

export function apiErrorBody(
  code: ApiErrorCode,
  error: string,
  details?: Record<string, unknown>
): ApiErrorBody {
  const body: ApiErrorBody = { error, code };
  if (details && Object.keys(details).length > 0) {
    body.details = details;
  }
  return body;
}

export function apiErrorResponse(
  code: ApiErrorCode,
  error: string,
  init?: { status?: number; details?: Record<string, unknown>; headers?: HeadersInit }
): Response {
  const status = init?.status ?? DEFAULT_STATUS[code] ?? 500;
  return Response.json(apiErrorBody(code, error, init?.details), {
    status,
    headers: init?.headers,
  });
}
