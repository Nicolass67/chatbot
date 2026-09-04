export function summarizeEmailToolResult(
  tool: string,
  output: unknown
): string {
  if (!output || typeof output !== "object") {
    return tool;
  }

  const data = output as Record<string, unknown>;

  if (typeof data.error === "string") {
    return `Erreur: ${data.error}`;
  }

  switch (tool) {
    case "email_list":
      return `Gmail · ${String(data.count ?? 0)} message(s)`;
    case "email_search":
      return `Gmail · recherche "${String(data.query ?? "")}" — ${String(data.count ?? 0)} résultat(s)`;
    case "email_get_thread":
      return `Gmail · thread ${String(data.threadId ?? "")} — ${String(data.messageCount ?? 0)} message(s)`;
    case "email_analyze":
      return `Gmail · analyse — ${String(data.itemCount ?? 0)} email(s)`;
    case "email_create_draft":
      return `Gmail · brouillon créé (${String(data.draftId ?? "?")})`;
    default:
      return tool;
  }
}
