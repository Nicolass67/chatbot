import type { Memory } from "@/lib/db/schema";

/**
 * Explicit, centralized weights for memory ranking (easy to tune + test).
 * Scores are normalized roughly to [0, 1] before weighting.
 */
export const MEMORY_RANK_WEIGHTS = {
  lexical: 0.35,
  entity: 0.2,
  conversation: 0.15,
  importance: 0.15,
  recency: 0.15,
} as const;

/** Half-life in days by category — preference/stable stay useful longer. */
export const MEMORY_RECENCY_HALF_LIFE_DAYS: Record<string, number> = {
  preference: 730,
  communication: 540,
  hardware: 540,
  project: 365,
  habit: 365,
  other: 180,
  /** Temporary / current-context style facts if ever tagged */
  temporary: 30,
  current: 60,
};

export type RankedMemory = {
  memory: Memory;
  score: number;
  parts: {
    lexical: number;
    entity: number;
    conversation: number;
    importance: number;
    recency: number;
  };
  reason: string;
};

function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .split(/\s+/)
    .map((w) => w.replace(/[^\p{L}\p{N}]/gu, ""))
    .filter((w) => w.length > 2);
}

function overlapScore(queryTokens: string[], doc: string): number {
  if (queryTokens.length === 0) return 0;
  const hay = doc.toLowerCase();
  let hits = 0;
  for (const t of queryTokens) {
    if (hay.includes(t)) hits += 1;
  }
  return Math.min(1, hits / queryTokens.length);
}

export function recencyScore(
  updatedAt: string,
  category: string,
  now = Date.now()
): number {
  const halfLife =
    MEMORY_RECENCY_HALF_LIFE_DAYS[category] ??
    MEMORY_RECENCY_HALF_LIFE_DAYS.other ??
    180;
  const ts = Date.parse(updatedAt);
  if (!Number.isFinite(ts)) return 0.5;
  const ageDays = Math.max(0, (now - ts) / (1000 * 60 * 60 * 24));
  // Exponential decay: 0.5^(age/halfLife)
  return Math.pow(0.5, ageDays / halfLife);
}

export function scoreMemory(input: {
  memory: Memory;
  primaryQuery: string;
  assistantHint?: string | null;
  entityLabels?: string[];
  now?: number;
}): RankedMemory {
  const { memory } = input;
  const primaryTokens = tokenize(input.primaryQuery);
  // Assistant hint used weakly for lexical only (contamination guard)
  const assistantTokens = tokenize(input.assistantHint ?? "").slice(0, 8);

  const lexicalPrimary = overlapScore(primaryTokens, memory.content);
  const lexicalAssist = overlapScore(assistantTokens, memory.content);
  const lexical = Math.min(1, lexicalPrimary + 0.25 * lexicalAssist);

  const entity = overlapScore(
    tokenize((input.entityLabels ?? []).join(" ")),
    `${memory.content} ${memory.category}`
  );

  const conversation = lexicalPrimary; // proxy: overlap with primary conversational query
  const importance = Math.min(1, Math.max(0, memory.importance ?? 0.5));
  const recency = recencyScore(
    memory.updatedAt,
    memory.category,
    input.now
  );

  const w = MEMORY_RANK_WEIGHTS;
  const score =
    w.lexical * lexical +
    w.entity * entity +
    w.conversation * conversation +
    w.importance * importance +
    w.recency * recency;

  const reasons: string[] = [];
  if (lexicalPrimary >= 0.4) reasons.push("lexical");
  if (entity >= 0.3) reasons.push("entity");
  if (importance >= 0.7) reasons.push("importance");
  if (recency >= 0.6) reasons.push("recency");
  if (reasons.length === 0) reasons.push("weak_match");

  return {
    memory,
    score,
    parts: { lexical, entity, conversation, importance, recency },
    reason: reasons.join("+"),
  };
}

export function rankAndSelectMemories(input: {
  candidates: Memory[];
  primaryQuery: string;
  assistantHint?: string | null;
  entityLabels?: string[];
  budget: number;
  minScore?: number;
}): { selected: RankedMemory[]; excluded: RankedMemory[] } {
  const minScore = input.minScore ?? 0.12;
  const ranked = input.candidates
    .map((memory) =>
      scoreMemory({
        memory,
        primaryQuery: input.primaryQuery,
        assistantHint: input.assistantHint,
        entityLabels: input.entityLabels,
      })
    )
    .sort((a, b) => b.score - a.score);

  if (input.budget <= 0) {
    return {
      selected: [],
      excluded: ranked.map((r) => ({
        ...r,
        reason: `${r.reason}|budget_zero`,
      })),
    };
  }

  const selected: RankedMemory[] = [];
  const excluded: RankedMemory[] = [];
  for (const r of ranked) {
    if (selected.length < input.budget && r.score >= minScore) {
      selected.push(r);
    } else {
      excluded.push({
        ...r,
        reason:
          r.score < minScore
            ? `${r.reason}|low_relevance`
            : `${r.reason}|over_budget`,
      });
    }
  }
  return { selected, excluded };
}
