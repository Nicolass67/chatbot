import type { EmailIntent } from "./types";

export const EMAIL_INTENT_TOOL_MAP: Record<
  Exclude<EmailIntent, "none">,
  readonly string[]
> = {
  list: ["email_list"],
  search: ["email_search"],
  read_thread: ["email_get_thread"],
  analyze: ["email_analyze"],
  draft: ["email_create_draft"],
};

export function emailIntentToTools(intent: EmailIntent): string[] {
  if (intent === "none") return [];
  return [...EMAIL_INTENT_TOOL_MAP[intent]];
}
