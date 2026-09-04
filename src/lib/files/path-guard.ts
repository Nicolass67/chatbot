/**
 * PathGuard — containment filesystem Windows (V1 pragmatique).
 *
 * Couverture V1 :
 * - traversal / `..` / absolute escape
 * - case-insensitive under-root
 * - UNC reject (sauf root UNC explicite — défaut refuse)
 * - ADS stream suffix reject
 * - symlinks détectés via lstat.isSymbolicLink → NO_FOLLOW reject
 * - external / subst : seulement si root explicitement enregistrée
 *
 * Gaps V2 (NE PAS considérer isSymbolicLink comme exhaustif) :
 * - junctions / reparse points Windows non exposés comme symlink
 * - détection reparse via Win32 API
 * - TOCTOU atomique via handles/fd
 */

import fs from "node:fs";
import path from "node:path";
import { FilesError } from "./types";

export type PathGuardOptions = {
  /** Si false (défaut), refuse tout chemin UNC même sous une root. */
  allowUncRoots?: boolean;
};

function isUncPath(p: string): boolean {
  return /^\\\\[^\\]+\\/.test(p) || /^\/\/[^/]+\//.test(p);
}

function hasAdsSuffix(p: string): boolean {
  // Drive letter "C:" is OK; "file.txt:Zone.Identifier" is not.
  const withoutDrive = /^[A-Za-z]:/.test(p) ? p.slice(2) : p;
  return withoutDrive.includes(":");
}

function normalizeForCompare(p: string): string {
  return path.normalize(p).replace(/\//g, "\\").toLowerCase();
}

function isPathInsideRoot(resolved: string, root: string): boolean {
  const r = normalizeForCompare(root);
  const t = normalizeForCompare(resolved);
  if (t === r) return true;
  const prefix = r.endsWith("\\") ? r : `${r}\\`;
  return t.startsWith(prefix);
}

function rejectReparseIfPresent(absolutePath: string): void {
  let st: fs.Stats;
  try {
    st = fs.lstatSync(absolutePath);
  } catch {
    return; // may not exist yet (mkdir parent checks separately)
  }

  if (st.isSymbolicLink()) {
    throw new FilesError(
      "REPARSE_REJECTED",
      "Les liens symboliques sont refusés (politique NO_FOLLOW V1)."
    );
  }

  // Best-effort junction detection: on Windows, readlink can succeed for junctions.
  if (process.platform === "win32") {
    try {
      fs.readlinkSync(absolutePath);
      throw new FilesError(
        "REPARSE_REJECTED",
        "Point de reparsing / junction détecté — refusé en V1."
      );
    } catch (err) {
      if (err instanceof FilesError) throw err;
      // EINVAL / not a link — OK
    }
  }
}

/**
 * Résout relativePath sous rootAbsolute et vérifie le containment.
 * Ne suit pas les symlinks (NO_FOLLOW best-effort).
 */
export function resolveUnderRoot(
  rootAbsolute: string,
  relativePath: string,
  options: PathGuardOptions = {}
): string {
  if (!rootAbsolute?.trim()) {
    throw new FilesError("ROOT_DENIED", "Root vide.");
  }

  const rootResolved = path.resolve(rootAbsolute);
  let rootCanonical = rootResolved;
  try {
    if (fs.existsSync(rootResolved)) {
      rootCanonical = fs.realpathSync.native(rootResolved);
    }
  } catch {
    rootCanonical = rootResolved;
  }

  if (!options.allowUncRoots && isUncPath(rootResolved)) {
    throw new FilesError(
      "UNC_REJECTED",
      "Les chemins UNC / réseau sont refusés par défaut."
    );
  }

  if (hasAdsSuffix(relativePath) || hasAdsSuffix(rootResolved)) {
    throw new FilesError(
      "ADS_REJECTED",
      "Alternate Data Streams refusés."
    );
  }

  const rel = relativePath.replace(/\//g, path.sep).replace(/^[/\\]+/, "");
  if (rel.split(path.sep).some((seg) => seg === "..")) {
    throw new FilesError("PATH_ESCAPE", "Segment '..' interdit.");
  }

  if (path.isAbsolute(rel) || isUncPath(rel)) {
    throw new FilesError(
      "PATH_ESCAPE",
      "Chemin absolu / UNC interdit dans relativePath."
    );
  }

  const joined = path.resolve(rootCanonical, rel || ".");
  if (!isPathInsideRoot(joined, rootCanonical)) {
    throw new FilesError(
      "PATH_ESCAPE",
      "Le chemin résolu sort de la root autorisée."
    );
  }

  // Canonicalize existing path without following final symlink when possible.
  let candidate = joined;
  if (fs.existsSync(joined)) {
    rejectReparseIfPresent(joined);
    try {
      const real = fs.realpathSync.native(joined);
      if (!isPathInsideRoot(real, rootCanonical)) {
        throw new FilesError(
          "PATH_ESCAPE",
          "realpath sort de la root autorisée."
        );
      }
      candidate = real;
    } catch (err) {
      if (err instanceof FilesError) throw err;
      candidate = joined;
    }
  } else {
    // Ensure parent chain stays in root
    let parent = path.dirname(joined);
    while (parent && isPathInsideRoot(parent, rootCanonical)) {
      if (fs.existsSync(parent)) {
        rejectReparseIfPresent(parent);
        break;
      }
      const next = path.dirname(parent);
      if (next === parent) break;
      parent = next;
    }
  }

  if (!isPathInsideRoot(candidate, rootCanonical)) {
    throw new FilesError("PATH_ESCAPE", "Contaiment PathGuard échoué.");
  }

  return candidate;
}

export function assertAbsoluteInRoot(
  absolutePath: string,
  rootAbsolute: string,
  options: PathGuardOptions = {}
): string {
  const rootResolved = path.resolve(rootAbsolute);
  const abs = path.resolve(absolutePath);
  if (!options.allowUncRoots && (isUncPath(abs) || isUncPath(rootResolved))) {
    throw new FilesError("UNC_REJECTED", "UNC refusé.");
  }
  if (hasAdsSuffix(abs)) {
    throw new FilesError("ADS_REJECTED", "ADS refusé.");
  }
  if (!isPathInsideRoot(abs, rootResolved)) {
    throw new FilesError("PATH_ESCAPE", "Hors root.");
  }
  if (fs.existsSync(abs)) {
    rejectReparseIfPresent(abs);
  }
  return abs;
}

export function toPosixRelative(rootAbsolute: string, absolutePath: string): string {
  const rel = path.relative(path.resolve(rootAbsolute), path.resolve(absolutePath));
  if (rel.startsWith("..") || path.isAbsolute(rel)) {
    throw new FilesError("PATH_ESCAPE", "relative() hors root.");
  }
  return rel.split(path.sep).join("/");
}
