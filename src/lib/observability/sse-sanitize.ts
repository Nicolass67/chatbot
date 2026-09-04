const REDACTED = "[redacted]";

function truncate(value: string, max: number): string {
  if (value.length <= max) return value;
  return `${value.slice(0, max)}…`;
}

function asRecord(input: unknown): Record<string, unknown> | null {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    return null;
  }
  return input as Record<string, unknown>;
}

/**
 * Résumé sûr pour SSE tool_start — évite de streamer corps/query email complets.
 */
export function sanitizeToolStartPayload(
  tool: string,
  input: unknown
): unknown {
  if (!tool.startsWith("email_")) return input;

  const record = asRecord(input);
  if (!record) return { input: REDACTED };

  switch (tool) {
    case "email_list":
      return {
        maxResults: record.maxResults,
        labelIds: record.labelIds,
      };
    case "email_search":
      return {
        query: REDACTED,
        maxResults: record.maxResults,
      };
    case "email_get_thread":
      return { threadId: record.threadId };
    case "email_analyze":
      return {
        threadId: record.threadId,
        messageIds: record.messageIds ? REDACTED : undefined,
        maxMessages: record.maxMessages,
      };
    case "email_create_draft":
      return {
        to: REDACTED,
        cc: record.cc ? REDACTED : undefined,
        bcc: record.bcc ? REDACTED : undefined,
        subject:
          typeof record.subject === "string"
            ? truncate(record.subject, 80)
            : REDACTED,
        bodyTextLength:
          typeof record.bodyText === "string"
            ? record.bodyText.length
            : undefined,
        threadId: record.threadId,
        inReplyToMessageId: record.inReplyToMessageId,
      };
    default:
      return { summary: REDACTED };
  }
}

export function assertSsePayloadSafe(json: string): void {
  const forbidden = [
    "access_token",
    "refresh_token",
    "confirmationToken",
    "encryptedAccessToken",
    "encryptedRefreshToken",
  ];
  for (const needle of forbidden) {
    if (json.includes(needle)) {
      throw new Error(`SSE payload contient une clé interdite: ${needle}`);
    }
  }
}
