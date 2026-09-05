/**
 * Contrat typé strict pour la décision mémoire LLM (Memory Post-Processor).
 * Le LLM ne produit que ce JSON — jamais d'accès SQLite / outils / fichiers.
 */

import { z } from "zod";
import { memoryCategorySchema } from "@/lib/settings/service";

export const MEMORY_DECISION_ACTIONS = [
  "create",
  "update",
  "delete",
  "ignore",
] as const;
export type MemoryDecisionAction = (typeof MEMORY_DECISION_ACTIONS)[number];

export const MEMORY_DECISION_TYPES = [
  "preference",
  "fact",
  "workflow",
  "project",
  "context",
  "other",
] as const;
export type MemoryDecisionType = (typeof MEMORY_DECISION_TYPES)[number];

export const memoryDecisionCandidateSchema = z.object({
  action: z.enum(MEMORY_DECISION_ACTIONS),
  memoryType: z.enum(MEMORY_DECISION_TYPES),
  content: z.string(),
  existingMemoryId: z.string().nullable().default(null),
  confidence: z.number().min(0).max(1),
  reason: z.string().default(""),
});

export const memoryDecisionPayloadSchema = z.object({
  candidates: z.array(memoryDecisionCandidateSchema).default([]),
});

export type MemoryDecisionCandidate = z.infer<
  typeof memoryDecisionCandidateSchema
>;
export type MemoryDecisionPayload = z.infer<typeof memoryDecisionPayloadSchema>;

export type ExistingMemorySnippet = {
  id: string;
  content: string;
  category: string;
  importance: number;
};

export type MemoryPostProcessorInput = {
  userMessage: string;
  assistantMessage: string;
  modelId: string;
  /** Turns récents bornés (pas tout l'historique). */
  recentTurns?: Array<{ role: "user" | "assistant"; content: string }>;
  existingMemories?: ExistingMemorySnippet[];
  signal?: AbortSignal;
};

export type AppliedMemoryChange = {
  action: "create" | "update" | "delete";
  id: string;
  content: string;
  category: string;
};

export type MemoryPostProcessorResult = {
  ok: boolean;
  changed: boolean;
  applied: AppliedMemoryChange[];
  ignoredCount: number;
  error?: string;
};

type MemoryCategory = z.infer<typeof memoryCategorySchema>;

/** Mappe le type décision LLM vers les catégories SQLite existantes. */
export function memoryTypeToCategory(
  memoryType: MemoryDecisionType
): MemoryCategory {
  switch (memoryType) {
    case "preference":
      return "preference";
    case "workflow":
      return "habit";
    case "project":
      return "project";
    case "fact":
    case "context":
    case "other":
    default:
      return "other";
  }
}
