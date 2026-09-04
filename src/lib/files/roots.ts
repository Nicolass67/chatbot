import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { and, eq } from "drizzle-orm";
import { nanoid } from "nanoid";
import { getDb } from "@/lib/db";
import { fileRoots } from "@/lib/db/schema";
import { DEFAULT_ROOT_LABELS } from "./constants";
import { assertAbsoluteInRoot } from "./path-guard";
import { FilesError, type FileRootRecord } from "./types";

function mapRoot(row: typeof fileRoots.$inferSelect): FileRootRecord {
  return {
    id: row.id,
    userId: row.userId,
    label: row.label,
    absolutePath: row.absolutePath,
    enabled: row.enabled,
    isDefault: row.isDefault,
    createdAt: row.createdAt,
  };
}

export function defaultDocumentsPath(): string {
  return path.join(os.homedir(), "Documents");
}

export function defaultDownloadsPath(): string {
  return path.join(os.homedir(), "Downloads");
}

export async function listFileRoots(userId: string): Promise<FileRootRecord[]> {
  const db = getDb();
  const rows = await db.query.fileRoots.findMany({
    where: eq(fileRoots.userId, userId),
  });
  return rows.map(mapRoot);
}

export async function listEnabledFileRoots(
  userId: string
): Promise<FileRootRecord[]> {
  const roots = await listFileRoots(userId);
  return roots.filter((r) => r.enabled);
}

export async function getFileRoot(
  userId: string,
  rootId: string
): Promise<FileRootRecord | null> {
  const db = getDb();
  const row = await db.query.fileRoots.findFirst({
    where: and(eq(fileRoots.id, rootId), eq(fileRoots.userId, userId)),
  });
  return row ? mapRoot(row) : null;
}

export async function ensureDefaultRoots(userId: string): Promise<FileRootRecord[]> {
  const existing = await listFileRoots(userId);
  if (existing.length > 0) return existing;

  const candidates = [
    {
      label: DEFAULT_ROOT_LABELS.documents,
      absolutePath: defaultDocumentsPath(),
    },
    {
      label: DEFAULT_ROOT_LABELS.downloads,
      absolutePath: defaultDownloadsPath(),
    },
  ];

  const db = getDb();
  const created: FileRootRecord[] = [];
  for (const c of candidates) {
    if (!fs.existsSync(c.absolutePath)) continue;
    const abs = path.resolve(c.absolutePath);
    const id = nanoid(16);
    await db.insert(fileRoots).values({
      id,
      userId,
      label: c.label,
      absolutePath: abs,
      enabled: true,
      isDefault: true,
    });
    created.push({
      id,
      userId,
      label: c.label,
      absolutePath: abs,
      enabled: true,
      isDefault: true,
      createdAt: new Date().toISOString(),
    });
  }
  return created;
}

export async function addFileRoot(input: {
  userId: string;
  label: string;
  absolutePath: string;
}): Promise<FileRootRecord> {
  const abs = path.resolve(input.absolutePath);
  if (abs.startsWith("\\\\") || abs.startsWith("//")) {
    throw new FilesError(
      "UNC_REJECTED",
      "Les racines UNC / réseau sont refusées par défaut."
    );
  }
  if (!fs.existsSync(abs) || !fs.statSync(abs).isDirectory()) {
    throw new FilesError("NOT_FOUND", "Le dossier root n'existe pas.");
  }
  // Self-containment check
  assertAbsoluteInRoot(abs, abs);

  const db = getDb();
  const id = nanoid(16);
  await db.insert(fileRoots).values({
    id,
    userId: input.userId,
    label: input.label.trim() || path.basename(abs),
    absolutePath: abs,
    enabled: true,
    isDefault: false,
  });
  const row = await getFileRoot(input.userId, id);
  if (!row) throw new FilesError("INTERNAL", "Échec création root.");
  return row;
}

export async function setFileRootEnabled(
  userId: string,
  rootId: string,
  enabled: boolean
): Promise<FileRootRecord> {
  const db = getDb();
  const existing = await getFileRoot(userId, rootId);
  if (!existing) throw new FilesError("NOT_FOUND", "Root introuvable.");
  await db
    .update(fileRoots)
    .set({ enabled })
    .where(and(eq(fileRoots.id, rootId), eq(fileRoots.userId, userId)));
  return { ...existing, enabled };
}

export async function removeFileRoot(
  userId: string,
  rootId: string
): Promise<void> {
  const db = getDb();
  const existing = await getFileRoot(userId, rootId);
  if (!existing) throw new FilesError("NOT_FOUND", "Root introuvable.");
  await db
    .delete(fileRoots)
    .where(and(eq(fileRoots.id, rootId), eq(fileRoots.userId, userId)));
}

export async function hasConfiguredRoots(userId: string): Promise<boolean> {
  const roots = await listEnabledFileRoots(userId);
  return roots.length > 0;
}
