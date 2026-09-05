import type { z } from "zod";
import { memoryCategorySchema } from "@/lib/settings/service";

export type NormalizedMemoryItem = {
  content: string;
  category: z.infer<typeof memoryCategorySchema>;
  importance: number;
};

/**
 * Les petits modèles renvoient souvent `memories: ["fait…"]` au lieu
 * d'objets `{ content, category, importance }`. On normalise avant Zod.
 */
export function coerceMemoryItem(raw: unknown): NormalizedMemoryItem | null {
  if (typeof raw === "string") {
    const content = raw.trim();
    if (content.length < 10) return null;
    return { content, category: "other", importance: 0.85 };
  }

  if (!raw || typeof raw !== "object") return null;
  const o = raw as Record<string, unknown>;
  const content = String(o.content ?? o.text ?? o.fact ?? o.memory ?? "").trim();
  if (content.length < 10) return null;

  const rawCategory = String(o.category ?? "other").trim().toLowerCase();
  const categoryAlias: Record<string, NormalizedMemoryItem["category"]> = {
    identity: "other",
    personal: "other",
    profile: "other",
    bio: "other",
    demographic: "other",
    demographie: "other",
    demography: "other",
    pref: "preference",
    preferences: "preference",
    prefs: "preference",
    hw: "hardware",
    tech: "hardware",
    projects: "project",
    habits: "habit",
    style: "communication",
    tone: "communication",
  };
  const mapped = categoryAlias[rawCategory] ?? rawCategory;
  const cat = memoryCategorySchema.safeParse(mapped);
  const category = cat.success ? cat.data : "other";

  let importance = 0.85;
  if (typeof o.importance === "number" && Number.isFinite(o.importance)) {
    importance = Math.min(1, Math.max(0, o.importance));
  } else if (typeof o.importance === "string") {
    const n = Number(o.importance);
    if (Number.isFinite(n)) importance = Math.min(1, Math.max(0, n));
  }
  // Insert exige ≥ 0.5 — remonter les scores trop bas du modèle.
  if (importance < 0.5) importance = 0.7;

  return { content, category, importance };
}

export function coerceMemoryItems(raw: unknown): NormalizedMemoryItem[] {
  if (!Array.isArray(raw)) return [];
  const out: NormalizedMemoryItem[] = [];
  for (const item of raw) {
    const coerced = coerceMemoryItem(item);
    if (coerced) out.push(coerced);
  }
  return out;
}
