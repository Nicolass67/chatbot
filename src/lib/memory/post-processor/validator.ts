import type {
  MemoryDecisionCandidate,
  MemoryDecisionPayload,
  ExistingMemorySnippet,
} from "./types";

export const MEMORY_MIN_CONFIDENCE = 0.7;
export const MEMORY_MIN_CONTENT_LENGTH = 10;

const SECRET_PATTERNS: RegExp[] = [
  /mot\s*de\s*passe/i,
  /password/i,
  /\btoken\b/i,
  /\bapi[_\s-]?key\b/i,
  /\bsecret\b/i,
  /\biban\b/i,
  /carte\s*(bancaire|bleue|de\s*crédit)/i,
  /\bcvv\b/i,
  /\b\d{13,19}\b/,
];

export interface ValidatedMemoryCandidate extends MemoryDecisionCandidate {
  accepted: boolean;
  rejectReason?: string;
}

function looksLikeSecret(content: string): boolean {
  return SECRET_PATTERNS.some((re) => re.test(content));
}

function findNearDuplicate(
  content: string,
  existing: ExistingMemorySnippet[]
): ExistingMemorySnippet | undefined {
  const needle = content.toLowerCase().trim();
  if (needle.length < 8) return undefined;
  const head = needle.slice(0, 40);
  return existing.find((m) => {
    const hay = m.content.toLowerCase();
    return hay.includes(head) || needle.includes(hay.slice(0, 40));
  });
}

/**
 * Memory Validator / Policy — indépendant de la décision LLM.
 * Peut refuser create/update/delete même si le LLM l'a proposé.
 */
export function validateMemoryDecisions(
  payload: MemoryDecisionPayload,
  existing: ExistingMemorySnippet[]
): ValidatedMemoryCandidate[] {
  const byId = new Map(existing.map((m) => [m.id, m]));
  const out: ValidatedMemoryCandidate[] = [];

  for (const raw of payload.candidates) {
    const content = raw.content.trim();
    if (raw.action === "ignore") {
      out.push({ ...raw, content, accepted: false, rejectReason: "ignore" });
      continue;
    }

    if (raw.confidence < MEMORY_MIN_CONFIDENCE) {
      out.push({
        ...raw,
        content,
        accepted: false,
        rejectReason: "confidence_below_threshold",
      });
      continue;
    }

    if (content.length < MEMORY_MIN_CONTENT_LENGTH) {
      out.push({
        ...raw,
        content,
        accepted: false,
        rejectReason: "content_too_short",
      });
      continue;
    }

    if (looksLikeSecret(content)) {
      out.push({
        ...raw,
        content,
        accepted: false,
        rejectReason: "secret_or_sensitive",
      });
      continue;
    }

    if (raw.action === "update" || raw.action === "delete") {
      const id = raw.existingMemoryId;
      if (!id || !byId.has(id)) {
        if (raw.action === "update" && raw.confidence >= 0.9) {
          out.push({
            ...raw,
            action: "create",
            existingMemoryId: null,
            content,
            accepted: true,
          });
          continue;
        }
        out.push({
          ...raw,
          content,
          accepted: false,
          rejectReason: "missing_or_unknown_existing_id",
        });
        continue;
      }
    }

    if (raw.action === "create") {
      const dup = findNearDuplicate(content, existing);
      if (dup) {
        out.push({
          ...raw,
          action: "update",
          existingMemoryId: dup.id,
          content,
          accepted: true,
        });
        continue;
      }
    }

    out.push({ ...raw, content, accepted: true });
  }

  return out;
}
