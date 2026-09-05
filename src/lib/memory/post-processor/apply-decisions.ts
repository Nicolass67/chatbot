import { eq } from "drizzle-orm";
import { getDb } from "@/lib/db";
import { memories } from "@/lib/db/schema";
import { insertMemoryIfValid } from "../extract";
import type { ValidatedMemoryCandidate } from "./validator";
import { memoryTypeToCategory, type AppliedMemoryChange } from "./types";

/**
 * Applique les décisions validées. Chaque op est isolée.
 * Rejouer un payload similaire reste globalement idempotent.
 */
export async function applyValidatedMemoryDecisions(
  candidates: ValidatedMemoryCandidate[]
): Promise<AppliedMemoryChange[]> {
  const applied: AppliedMemoryChange[] = [];
  const db = getDb();
  const now = new Date().toISOString();

  for (const c of candidates) {
    if (!c.accepted) continue;

    try {
      if (c.action === "create") {
        const inserted = await insertMemoryIfValid({
          content: c.content,
          category: memoryTypeToCategory(c.memoryType),
          importance: Math.max(0.7, c.confidence),
        });
        if (inserted) {
          applied.push({
            action: "create",
            id: inserted.id,
            content: inserted.content,
            category: inserted.category,
          });
        }
        continue;
      }

      if (c.action === "update" && c.existingMemoryId) {
        const category = memoryTypeToCategory(c.memoryType);
        await db
          .update(memories)
          .set({
            content: c.content,
            category,
            importance: Math.max(0.7, c.confidence),
            updatedAt: now,
          })
          .where(eq(memories.id, c.existingMemoryId));

        const row = await db.query.memories.findFirst({
          where: (m, { eq: e }) => e(m.id, c.existingMemoryId!),
        });
        if (row) {
          applied.push({
            action: "update",
            id: row.id,
            content: row.content,
            category: row.category,
          });
        }
        continue;
      }

      if (c.action === "delete" && c.existingMemoryId) {
        const row = await db.query.memories.findFirst({
          where: (m, { eq: e }) => e(m.id, c.existingMemoryId!),
        });
        if (!row) continue;
        await db.delete(memories).where(eq(memories.id, c.existingMemoryId));
        applied.push({
          action: "delete",
          id: row.id,
          content: row.content,
          category: row.category,
        });
      }
    } catch {
      continue;
    }
  }

  return applied;
}
