import { and, eq, lt } from "drizzle-orm";
import { nanoid } from "nanoid";
import { getDb } from "@/lib/db";
import { fileReferences } from "@/lib/db/schema";
import { FILE_REF_TTL_MS } from "./constants";
import type { FileReferenceRecord } from "./types";

function mapRef(row: typeof fileReferences.$inferSelect): FileReferenceRecord {
  return {
    id: row.id,
    userId: row.userId,
    rootId: row.rootId,
    relativePath: row.relativePath,
    displayName: row.displayName,
    sizeBytes: row.sizeBytes,
    mtimeMs: row.mtimeMs,
    createdAt: row.createdAt,
    expiresAt: row.expiresAt,
  };
}

export async function mintFileReference(input: {
  userId: string;
  rootId: string;
  relativePath: string;
  displayName: string;
  sizeBytes: number;
  mtimeMs: number;
  ttlMs?: number;
}): Promise<FileReferenceRecord> {
  const db = getDb();
  const now = Date.now();
  const ttlMs = input.ttlMs ?? FILE_REF_TTL_MS;
  const expiresAt = new Date(now + ttlMs).toISOString();
  const relativePath = input.relativePath.replace(/\\/g, "/");

  // Réutilise une ref non expirée pour stabiliser `file=` dans l'URL (F5 / partage).
  const existing = await db.query.fileReferences.findFirst({
    where: and(
      eq(fileReferences.userId, input.userId),
      eq(fileReferences.rootId, input.rootId),
      eq(fileReferences.relativePath, relativePath)
    ),
    orderBy: (t, { desc }) => [desc(t.createdAt)],
  });

  if (existing && new Date(existing.expiresAt).getTime() > now) {
    await db
      .update(fileReferences)
      .set({
        displayName: input.displayName,
        sizeBytes: input.sizeBytes,
        mtimeMs: input.mtimeMs,
        expiresAt,
      })
      .where(eq(fileReferences.id, existing.id));
    return {
      id: existing.id,
      userId: existing.userId,
      rootId: existing.rootId,
      relativePath: existing.relativePath,
      displayName: input.displayName,
      sizeBytes: input.sizeBytes,
      mtimeMs: input.mtimeMs,
      createdAt: existing.createdAt,
      expiresAt,
    };
  }

  const id = nanoid(20);
  await db.insert(fileReferences).values({
    id,
    userId: input.userId,
    rootId: input.rootId,
    relativePath,
    displayName: input.displayName,
    sizeBytes: input.sizeBytes,
    mtimeMs: input.mtimeMs,
    expiresAt,
  });

  return {
    id,
    userId: input.userId,
    rootId: input.rootId,
    relativePath,
    displayName: input.displayName,
    sizeBytes: input.sizeBytes,
    mtimeMs: input.mtimeMs,
    createdAt: new Date(now).toISOString(),
    expiresAt,
  };
}

export async function getFileReference(
  userId: string,
  fileId: string
): Promise<FileReferenceRecord | null> {
  const db = getDb();
  const row = await db.query.fileReferences.findFirst({
    where: and(
      eq(fileReferences.id, fileId),
      eq(fileReferences.userId, userId)
    ),
  });
  return row ? mapRef(row) : null;
}

export async function purgeExpiredFileReferences(
  now = Date.now()
): Promise<number> {
  const db = getDb();
  const iso = new Date(now).toISOString();
  const result = await db
    .delete(fileReferences)
    .where(lt(fileReferences.expiresAt, iso));
  return result.changes ?? 0;
}
