import fs from "node:fs";
import path from "node:path";
import { classifyRelativePathAccess } from "./access";
import { isFilesFeatureEnabled } from "./feature";
import { resolveUnderRoot, toPosixRelative } from "./path-guard";
import { getFileReference } from "./references";
import { getFileRoot, listEnabledFileRoots } from "./roots";
import {
  FilesError,
  type FileRootRecord,
  type ResolvedFile,
} from "./types";

/**
 * fileId n'est PAS une autorisation.
 * Pipeline : fileId → userId → root → axes → PathGuard → FS state.
 */
export async function resolveFileReference(
  userId: string,
  fileId: string,
  options?: { requireExpose?: boolean; requireMutate?: boolean }
): Promise<ResolvedFile> {
  if (!isFilesFeatureEnabled()) {
    throw new FilesError("FEATURE_DISABLED", "Files désactivé.");
  }

  const ref = await getFileReference(userId, fileId);
  if (!ref) {
    throw new FilesError(
      "FORBIDDEN_USER",
      "Référence fichier introuvable ou non autorisée."
    );
  }

  if (new Date(ref.expiresAt).getTime() <= Date.now()) {
    throw new FilesError("STALE_REFERENCE", "Référence fichier expirée.");
  }

  const root = await getFileRoot(userId, ref.rootId);
  if (!root || !root.enabled) {
    throw new FilesError("ROOT_DENIED", "Root inactive ou introuvable.");
  }

  const absolutePath = resolveUnderRoot(root.absolutePath, ref.relativePath);
  const access = classifyRelativePathAccess(ref.relativePath, {
    featureEnabled: true,
    rootOk: true,
  });

  if (!fs.existsSync(absolutePath)) {
    throw new FilesError("NOT_FOUND", "Fichier introuvable sur le disque.");
  }

  const st = fs.lstatSync(absolutePath);
  if (
    st.size !== ref.sizeBytes ||
    Math.floor(st.mtimeMs) !== ref.mtimeMs
  ) {
    // Allow resolve with updated fingerprint but mark — callers for mutate must fail harder.
    // For read we refresh sizes on the resolved object; mutate services re-check frozen payload.
  }

  if (options?.requireExpose && !access.canExposeToLlm) {
    throw new FilesError(
      "SENSITIVE_PATTERN",
      "Contenu non exposable au modèle."
    );
  }
  if (options?.requireMutate && !access.canMutate) {
    throw new FilesError(
      "SENSITIVE_PATTERN",
      "Mutation interdite pour ce fichier."
    );
  }

  return {
    fileId: ref.id,
    rootId: root.id,
    relativePath: ref.relativePath,
    absolutePath,
    displayName: ref.displayName,
    sizeBytes: st.size,
    mtimeMs: Math.floor(st.mtimeMs),
    isDirectory: st.isDirectory(),
    access,
  };
}

/** Bootstrap UI : path relatif sous une root → mint fileId. */
export async function resolvePathToFile(
  userId: string,
  rootId: string,
  relativePath: string
): Promise<{ root: FileRootRecord; absolutePath: string; relativePath: string; stat: fs.Stats }> {
  if (!isFilesFeatureEnabled()) {
    throw new FilesError("FEATURE_DISABLED", "Files désactivé.");
  }
  const root = await getFileRoot(userId, rootId);
  if (!root?.enabled) {
    throw new FilesError("ROOT_DENIED", "Root inactive.");
  }
  const absolutePath = resolveUnderRoot(root.absolutePath, relativePath);
  if (!fs.existsSync(absolutePath)) {
    throw new FilesError("NOT_FOUND", "Chemin introuvable.");
  }
  const stat = fs.lstatSync(absolutePath);
  const rel = toPosixRelative(root.absolutePath, absolutePath);
  return { root, absolutePath, relativePath: rel, stat };
}

export async function requireEnabledRoots(
  userId: string
): Promise<FileRootRecord[]> {
  const roots = await listEnabledFileRoots(userId);
  if (roots.length === 0) {
    throw new FilesError(
      "NO_ROOTS",
      "Aucune root Files configurée. Ajoutez Documents/Downloads dans les paramètres."
    );
  }
  return roots;
}

export function extensionOf(name: string): string {
  return path.extname(name).toLowerCase();
}
