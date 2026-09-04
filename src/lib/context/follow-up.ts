/**
 * Follow-up retrieval query expansion.
 * Current user message is always the primary signal.
 * Assistant excerpt is secondary only — never treated as ground truth.
 */

export interface FollowUpExpansionInput {
  currentUserMessage: string;
  previousUserMessages?: string[];
  lastAssistantExcerpt?: string | null;
  activeEntityLabels?: string[];
  expand: boolean;
}

export interface FollowUpExpansionResult {
  retrievalQuery: string;
  /** Primary part (current + entities + previous user) */
  primaryQuery: string;
  /** Secondary assistant hint (low weight for ranking only) */
  assistantHint: string | null;
}

const MAX_ASSISTANT_EXCERPT = 240;
const MAX_PREV_USER = 400;

export function expandRetrievalQuery(
  input: FollowUpExpansionInput
): FollowUpExpansionResult {
  const current = input.currentUserMessage.trim();
  if (!input.expand) {
    return {
      retrievalQuery: current,
      primaryQuery: current,
      assistantHint: null,
    };
  }

  const entities = (input.activeEntityLabels ?? [])
    .map((s) => s.trim())
    .filter(Boolean)
    .slice(0, 3)
    .join(" ");

  const prevUsers = (input.previousUserMessages ?? [])
    .map((s) => s.trim())
    .filter(Boolean)
    .slice(-2)
    .join(" ")
    .slice(0, MAX_PREV_USER);

  const primaryParts = [current, entities, prevUsers].filter(Boolean);
  const primaryQuery = primaryParts.join(" ").replace(/\s+/g, " ").trim();

  const assistantRaw = input.lastAssistantExcerpt?.trim() ?? "";
  const assistantHint =
    assistantRaw.length > 0
      ? assistantRaw.slice(0, MAX_ASSISTANT_EXCERPT)
      : null;

  // Assistant text is appended lightly for FTS recall only — ranking
  // must not treat it as authoritative (see memory ranking weights).
  const retrievalQuery = assistantHint
    ? `${primaryQuery} ${assistantHint}`.replace(/\s+/g, " ").trim()
    : primaryQuery;

  return { retrievalQuery, primaryQuery, assistantHint };
}
