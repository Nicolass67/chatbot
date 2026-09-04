const SENSITIVE_KEY =
  /token|secret|password|authorization|access_token|refresh_token|confirmation/i;

export function redactToken(value: string): string {
  const trimmed = value.trim();
  if (trimmed.length <= 8) return "[redacted]";
  return `${trimmed.slice(0, 4)}…${trimmed.slice(-4)}`;
}

export function redactEmailBody(body: string, maxPreview = 0): string {
  const trimmed = body.trim();
  if (maxPreview <= 0 || trimmed.length === 0) return "[redacted]";
  if (trimmed.length <= maxPreview) return trimmed;
  return `${trimmed.slice(0, maxPreview)}…`;
}

export function redactSecretsInObject(
  value: unknown,
  depth = 0
): unknown {
  if (depth > 6) return "[redacted]";
  if (value === null || value === undefined) return value;
  if (typeof value === "string") return value;
  if (Array.isArray(value)) {
    return value.map((item) => redactSecretsInObject(item, depth + 1));
  }
  if (typeof value !== "object") return value;

  const out: Record<string, unknown> = {};
  for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
    if (SENSITIVE_KEY.test(key)) {
      out[key] =
        typeof nested === "string" ? redactToken(nested) : "[redacted]";
      continue;
    }
    out[key] = redactSecretsInObject(nested, depth + 1);
  }
  return out;
}

export function safeActionMetadata(
  metadata?: Record<string, unknown>
): Record<string, unknown> {
  const redacted = redactSecretsInObject(metadata ?? {});
  return typeof redacted === "object" && redacted !== null && !Array.isArray(redacted)
    ? (redacted as Record<string, unknown>)
    : {};
}

export function safeJsonStringify(value: unknown): string {
  return JSON.stringify(redactSecretsInObject(value));
}
