import { desc, inArray } from "drizzle-orm";
import { getDb } from "@/lib/db";
import { memories } from "@/lib/db/schema";
import type { WritingPreference } from "./types";

const WRITING_CATEGORIES = ["communication", "preference"] as const;

export async function loadWritingPreferences(
  limit = 8
): Promise<WritingPreference[]> {
  const db = getDb();
  const rows = await db.query.memories.findMany({
    where: inArray(memories.category, [...WRITING_CATEGORIES]),
    orderBy: [desc(memories.importance), desc(memories.updatedAt)],
    limit,
  });

  return rows.map((row) => ({
    id: row.id,
    content: row.content,
    category: row.category,
    importance: row.importance,
  }));
}

export function formatWritingPreferencesBlock(
  preferences: WritingPreference[]
): string {
  if (preferences.length === 0) {
    return `<email_writing_preferences>
Aucune préférence de rédaction mémorisée. Utilise un ton professionnel, clair et concis en français.
</email_writing_preferences>`;
  }

  const lines = preferences.map(
    (pref, index) => `${index + 1}. [${pref.category}] ${pref.content.trim()}`
  );

  return `<email_writing_preferences>
Préférences de rédaction email de l'utilisateur (à appliquer aux brouillons) :
${lines.join("\n")}
</email_writing_preferences>`;
}

export async function buildEmailDraftWritingBlock(): Promise<string> {
  const preferences = await loadWritingPreferences();
  return formatWritingPreferencesBlock(preferences);
}
