import fs from "node:fs";
import path from "node:path";
import { and, eq } from "drizzle-orm";
import { nanoid } from "nanoid";
import {
  chunkText,
  extractTextFromFile,
  guessMimeFromFilename,
} from "@/lib/documents/extract";
import { getDb, getSqlite } from "@/lib/db";
import { fileIndexChunks, fileIndexEntries } from "@/lib/db/schema";
import { isSensitiveRelativePath } from "./access";
import { INDEXABLE_EXTENSIONS, LIMITS } from "./constants";
import { resolveUnderRoot, toPosixRelative } from "./path-guard";
import type { FileRootRecord } from "./types";

export async function purgeIndexEntry(input: {
  userId: string;
  rootId: string;
  relativePath: string;
}): Promise<void> {
  const db = getDb();
  const rel = input.relativePath.replace(/\\/g, "/");
  const existing = await db.query.fileIndexEntries.findFirst({
    where: and(
      eq(fileIndexEntries.userId, input.userId),
      eq(fileIndexEntries.rootId, input.rootId),
      eq(fileIndexEntries.relativePath, rel)
    ),
  });
  if (!existing) return;
  await db
    .delete(fileIndexChunks)
    .where(eq(fileIndexChunks.entryId, existing.id));
  await db.delete(fileIndexEntries).where(eq(fileIndexEntries.id, existing.id));
}

/** Chemins relatifs indexés pour une root (badge UI / filtre). */
export async function listIndexedRelativePaths(
  userId: string,
  rootId: string,
  relativePaths?: string[]
): Promise<Set<string>> {
  const paths = relativePaths
    ?.map((p) => p.replace(/\\/g, "/"))
    .filter((p) => p.length > 0);
  if (paths && paths.length === 0) return new Set();

  // Page list: ne charge que les chemins visibles (évite de matérialiser tout l'index root).
  if (paths && paths.length > 0 && paths.length <= 500) {
    const sqlite = getSqlite();
    const placeholders = paths.map(() => "?").join(",");
    const rows = sqlite
      .prepare(
        `SELECT relative_path AS relativePath
         FROM file_index_entries
         WHERE user_id = ? AND root_id = ?
           AND relative_path IN (${placeholders})`
      )
      .all(userId, rootId, ...paths) as Array<{ relativePath: string }>;
    return new Set(
      rows.map((r) => String(r.relativePath).replace(/\\/g, "/"))
    );
  }

  const db = getDb();
  const rows = await db.query.fileIndexEntries.findMany({
    where: and(
      eq(fileIndexEntries.userId, userId),
      eq(fileIndexEntries.rootId, rootId)
    ),
    columns: { relativePath: true },
  });
  return new Set(rows.map((r) => r.relativePath.replace(/\\/g, "/")));
}

export async function purgeIndexForRoot(
  userId: string,
  rootId: string
): Promise<void> {
  const sqlite = getSqlite();
  const tx = sqlite.transaction(() => {
    sqlite
      .prepare(
        `DELETE FROM file_index_chunks
         WHERE entry_id IN (
           SELECT id FROM file_index_entries
           WHERE user_id = ? AND root_id = ?
         )`
      )
      .run(userId, rootId);
    sqlite
      .prepare(
        `DELETE FROM file_index_entries WHERE user_id = ? AND root_id = ?`
      )
      .run(userId, rootId);
  });
  tx();
}

export async function indexRootFiles(input: {
  userId: string;
  root: FileRootRecord;
  maxFiles?: number;
}): Promise<{ indexed: number; skipped: number }> {
  let indexed = 0;
  let skipped = 0;
  const maxFiles = input.maxFiles ?? 2000;
  const stack = [input.root.absolutePath];

  while (stack.length > 0 && indexed + skipped < maxFiles * 2) {
    const dir = stack.pop()!;
    let ents: fs.Dirent[];
    try {
      ents = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const ent of ents) {
      const abs = path.join(dir, ent.name);
      let st: fs.Stats;
      try {
        st = fs.lstatSync(abs);
      } catch {
        continue;
      }
      if (st.isSymbolicLink()) {
        skipped += 1;
        continue;
      }
      if (st.isDirectory()) {
        stack.push(abs);
        continue;
      }

      const rel = toPosixRelative(input.root.absolutePath, abs);
      if (isSensitiveRelativePath(rel)) {
        await purgeIndexEntry({
          userId: input.userId,
          rootId: input.root.id,
          relativePath: rel,
        });
        skipped += 1;
        continue;
      }

      const ext = path.extname(ent.name).toLowerCase();
      if (!INDEXABLE_EXTENSIONS.has(ext)) {
        skipped += 1;
        continue;
      }
      if (st.size > LIMITS.indexMaxFileBytes) {
        skipped += 1;
        continue;
      }

      try {
        await indexSingleFile({
          userId: input.userId,
          root: input.root,
          absolutePath: abs,
          relativePath: rel,
          sizeBytes: st.size,
          mtimeMs: Math.floor(st.mtimeMs),
        });
        indexed += 1;
      } catch {
        skipped += 1;
      }
      if (indexed >= maxFiles) break;
    }
  }

  return { indexed, skipped };
}

async function indexSingleFile(input: {
  userId: string;
  root: FileRootRecord;
  absolutePath: string;
  relativePath: string;
  sizeBytes: number;
  mtimeMs: number;
}): Promise<void> {
  if (isSensitiveRelativePath(input.relativePath)) {
    await purgeIndexEntry({
      userId: input.userId,
      rootId: input.root.id,
      relativePath: input.relativePath,
    });
    return;
  }

  const db = getDb();
  const rel = input.relativePath.replace(/\\/g, "/");
  const existing = await db.query.fileIndexEntries.findFirst({
    where: and(
      eq(fileIndexEntries.userId, input.userId),
      eq(fileIndexEntries.rootId, input.root.id),
      eq(fileIndexEntries.relativePath, rel)
    ),
    columns: { id: true, sizeBytes: true, mtimeMs: true },
  });
  if (
    existing &&
    existing.sizeBytes === input.sizeBytes &&
    existing.mtimeMs === input.mtimeMs
  ) {
    return;
  }

  const mime = guessMimeFromFilename(path.basename(input.relativePath));
  const text = await extractTextFromFile(
    input.absolutePath,
    mime,
    path.basename(input.relativePath)
  );
  const chunks = chunkText(text);
  if (chunks.length === 0) return;

  await purgeIndexEntry({
    userId: input.userId,
    rootId: input.root.id,
    relativePath: input.relativePath,
  });

  const entryId = nanoid(16);
  await db.insert(fileIndexEntries).values({
    id: entryId,
    userId: input.userId,
    rootId: input.root.id,
    relativePath: rel,
    sizeBytes: input.sizeBytes,
    mtimeMs: input.mtimeMs,
    mime,
  });

  for (let i = 0; i < chunks.length; i += 1) {
    await db.insert(fileIndexChunks).values({
      id: nanoid(16),
      entryId,
      userId: input.userId,
      rootId: input.root.id,
      chunkIndex: i,
      content: chunks[i],
    });
  }
}

export async function searchFileIndexPassages(input: {
  userId: string;
  rootId?: string;
  relativePath?: string;
  query: string;
  limit?: number;
}): Promise<Array<{ content: string; relativePath: string; score: number }>> {
  const q = input.query
    .trim()
    .split(/\s+/)
    .filter((w) => w.length > 2)
    .map((w) => `"${w.replace(/"/g, "")}"`)
    .join(" OR ");
  if (!q) return [];

  const sqlite = getSqlite();
  const limit = input.limit ?? 5;

  let sql = `
    SELECT fic.content, fie.relative_path as relativePath, bm25(file_index_chunks_fts) as score
    FROM file_index_chunks_fts fts
    JOIN file_index_chunks fic ON fic.rowid = fts.rowid
    JOIN file_index_entries fie ON fie.id = fic.entry_id
    WHERE file_index_chunks_fts MATCH ?
      AND fic.user_id = ?
  `;
  const params: unknown[] = [q, input.userId];
  if (input.rootId) {
    sql += ` AND fic.root_id = ?`;
    params.push(input.rootId);
  }
  if (input.relativePath) {
    sql += ` AND fie.relative_path = ?`;
    params.push(input.relativePath.replace(/\\/g, "/"));
  }
  sql += ` ORDER BY score LIMIT ?`;
  params.push(limit);

  const rows = sqlite.prepare(sql).all(...params) as Array<{
    content: string;
    relativePath: string;
    score: number;
  }>;

  // Re-check sensitivity — never return protected content
  return rows.filter((r) => !isSensitiveRelativePath(r.relativePath));
}

export async function ensurePathStillIndexable(
  userId: string,
  rootId: string,
  relativePath: string
): Promise<void> {
  if (isSensitiveRelativePath(relativePath)) {
    await purgeIndexEntry({ userId, rootId, relativePath });
  }
}

/** Helper used when resolving absolute path under root for index. */
export function resolveForIndex(
  rootAbsolute: string,
  relativePath: string
): string {
  return resolveUnderRoot(rootAbsolute, relativePath);
}
