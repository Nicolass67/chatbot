/**
 * Compress tool results for chat context: keep metadata + useful payload,
 * then size-limit. Avoid blind truncation of structured errors.
 */

const DEFAULT_MAX_CHARS = 2000;

export function compressToolResultForContext(
  result: unknown,
  options?: { maxChars?: number }
): string {
  const maxChars = options?.maxChars ?? DEFAULT_MAX_CHARS;

  if (result == null) return "null";

  if (typeof result === "string") {
    return truncateSmart(result, maxChars);
  }

  if (typeof result !== "object") {
    return truncateSmart(String(result), maxChars);
  }

  const obj = result as Record<string, unknown>;
  const compressed: Record<string, unknown> = {};

  if ("ok" in obj) compressed.ok = obj.ok;
  if ("error" in obj) compressed.error = obj.error;
  if ("status" in obj) compressed.status = obj.status;
  if ("message" in obj) compressed.message = obj.message;
  if ("query" in obj) compressed.query = obj.query;

  if (Array.isArray(obj.results)) {
    compressed.results = (obj.results as unknown[]).slice(0, 8).map((r) => {
      if (!r || typeof r !== "object") return r;
      const hit = r as Record<string, unknown>;
      return {
        title: hit.title,
        url: hit.url,
        snippet:
          typeof hit.snippet === "string"
            ? hit.snippet.slice(0, 200)
            : hit.snippet,
      };
    });
    if ((obj.results as unknown[]).length > 8) {
      compressed.resultsOmitted = (obj.results as unknown[]).length - 8;
    }
  } else if (Array.isArray(obj.hits)) {
    compressed.hits = (obj.hits as unknown[]).slice(0, 8);
  } else if (typeof obj.content === "string") {
    compressed.content = truncateSmart(obj.content, Math.floor(maxChars * 0.7));
  } else if (typeof obj.text === "string") {
    compressed.text = truncateSmart(obj.text, Math.floor(maxChars * 0.7));
  } else {
    // Generic: shallow copy top-level, stringify with budget
    for (const [k, v] of Object.entries(obj)) {
      if (compressed[k] !== undefined) continue;
      compressed[k] = v;
    }
  }

  let json = JSON.stringify(compressed);
  if (json.length <= maxChars) return json;

  // Progressive shrink of large string fields — keep valid JSON
  for (const key of ["content", "text", "message", "body"]) {
    if (typeof compressed[key] === "string") {
      compressed[key] = truncateSmart(
        compressed[key] as string,
        Math.max(80, Math.floor(maxChars / 4))
      );
      json = JSON.stringify(compressed);
      if (json.length <= maxChars) return json;
    }
  }

  if (Array.isArray(compressed.results)) {
    while (
      (compressed.results as unknown[]).length > 1 &&
      JSON.stringify(compressed).length > maxChars
    ) {
      (compressed.results as unknown[]).pop();
      compressed.resultsOmitted =
        (typeof compressed.resultsOmitted === "number"
          ? compressed.resultsOmitted
          : 0) + 1;
    }
    json = JSON.stringify(compressed);
    if (json.length <= maxChars) return json;
  }

  // Last resort: minimal valid JSON summary
  return JSON.stringify({
    ok: compressed.ok,
    error: compressed.error,
    status: compressed.status,
    message:
      typeof compressed.message === "string"
        ? truncateSmart(compressed.message, 200)
        : "result_truncated",
    truncated: true,
  });
}

function truncateSmart(text: string, max: number): string {
  if (text.length <= max) return text;
  return `${text.slice(0, Math.max(0, max - 16))}\n…[tronqué]`;
}
