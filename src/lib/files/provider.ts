import fs from "node:fs";
import path from "node:path";
import {
  SEARCH_MAX_RESULTS,
  SEARCH_SKIP_DIR_NAMES,
  SEARCH_SNIPPET_MAX_CHARS,
  WALK_MAX_DEPTH,
  WALK_MAX_FILES,
  WALK_TIMEOUT_MS,
} from "./constants";
import { resolveUnderRoot, toPosixRelative } from "./path-guard";
import { mintFileReference, mintFileReferencesBatch } from "./references";
import type {
  FileListEntry,
  FileRootRecord,
  FileSearchHit,
} from "./types";
import { extensionOf } from "./resolve";

export type MetadataSearchFilters = {
  query?: string;
  extensions?: string[];
  mtimeFromMs?: number;
  mtimeToMs?: number;
  minSize?: number;
  maxSize?: number;
  maxResults?: number;
};

const QUERY_STOPWORDS = new Set([
  "a",
  "au",
  "aux",
  "avec",
  "bonjour",
  "ce",
  "ces",
  "cette",
  "cherche",
  "chercher",
  "dans",
  "de",
  "des",
  "donne",
  "donner",
  "du",
  "en",
  "et",
  "fichier",
  "fichiers",
  "hello",
  "hi",
  "il",
  "je",
  "l",
  "la",
  "le",
  "les",
  "ma",
  "me",
  "mes",
  "moi",
  "mon",
  "montre",
  "montrer",
  "ou",
  "ouvre",
  "ouvrir",
  "par",
  "peux",
  "please",
  "plait",
  "pour",
  "puis",
  "recupere",
  "recuperer",
  "sa",
  "salut",
  "se",
  "ses",
  "son",
  "stp",
  "sur",
  "svp",
  "ta",
  "te",
  "tes",
  "ton",
  "trouve",
  "trouver",
  "tu",
  "un",
  "une",
  "veux",
  "voir",
  "y",
]);

function normalizeSearchText(s: string): string {
  return s
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/['’]/g, " ");
}

/** Tokens significatifs (ignore « ma », « le », etc.). */
export function queryTokens(query: string): string[] {
  return normalizeSearchText(query)
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length >= 2 && !QUERY_STOPWORDS.has(t));
}

/**
 * Score nom/chemin vs requête.
 * 2 tokens → les deux requis (évite « carte » seul → carte grise / vitale).
 * 3+ tokens → majorité stricte (~2/3).
 */
export function nameScore(haystack: string, query: string): number {
  const f = normalizeSearchText(haystack);
  const q = normalizeSearchText(query).trim();
  if (!q) return 0;
  if (f === q) return 100;
  if (f.includes(q)) return 90;

  const parts = queryTokens(query);
  if (parts.length === 0) return 0;

  let matched = 0;
  for (const p of parts) {
    if (tokenMatchesHaystack(f, p)) matched += 1;
  }
  if (matched === 0) return 0;
  if (parts.length === 2 && matched < 2) return 0;
  if (parts.length >= 3 && matched < Math.ceil(parts.length * (2 / 3))) {
    return 0;
  }

  const ratio = matched / parts.length;
  let score = Math.round(30 + ratio * 45);
  if (matched === parts.length) score += 15;
  const base = f.split(/[/\\]/).pop() ?? f;
  if (base.startsWith(parts[0]!)) score += 8;
  // Bonus documents d’identité explicites (CNI / nationale).
  if (parts.includes("identite") && (f.includes("cni") || f.includes("nationale"))) {
    score += 10;
  }
  return Math.min(99, score);
}

/** Synonymes légers sans hardcoder tout le domaine. */
function tokenMatchesHaystack(haystack: string, token: string): boolean {
  if (haystack.includes(token)) return true;
  if (token === "identite" && haystack.includes("cni")) return true;
  if (token === "cni" && haystack.includes("identite")) return true;
  // CNI.pdf doit répondre à « carte d'identité » (pas seulement « identité »).
  if (token === "carte" && haystack.includes("cni")) return true;
  return false;
}

/** Garde les hits proches du meilleur score (coupe le bruit faible). */
export function keepStrongSearchHits<T extends { score: number }>(
  hits: T[],
  options?: { ratio?: number; minAbs?: number; max?: number }
): T[] {
  if (hits.length === 0) return hits;
  const ratio = options?.ratio ?? 0.82;
  const minAbs = options?.minAbs ?? 50;
  const max = options?.max ?? 8;
  const best = hits[0]!.score;
  const floor = Math.max(minAbs, best * ratio);
  return hits.filter((h) => h.score >= floor).slice(0, max);
}

export async function listDirectory(input: {
  userId: string;
  root: FileRootRecord;
  relativePath: string;
  limit?: number;
  cursor?: string;
}): Promise<{
  entries: FileListEntry[];
  nextCursor: string | null;
  totalListed: number;
}> {
  const abs = resolveUnderRoot(input.root.absolutePath, input.relativePath);
  const st = fs.lstatSync(abs);
  if (!st.isDirectory()) {
    throw new Error("Le chemin n'est pas un dossier.");
  }

  const dirents = fs.readdirSync(abs, { withFileTypes: true });
  const names: string[] = [];
  for (const d of dirents) {
    // Junctions / symlinks Windows (ex. « Ma musique ») : on les ignore
    // pour que le total corresponde aux entrées réellement listables.
    if (d.isSymbolicLink()) continue;
    const childAbs = path.join(abs, d.name);
    try {
      const st = fs.lstatSync(childAbs);
      if (st.isSymbolicLink()) continue;
    } catch {
      continue;
    }
    names.push(d.name);
  }
  names.sort((a, b) =>
    a.localeCompare(b, "fr", { sensitivity: "base", numeric: true })
  );

  const limit = Math.min(Math.max(input.limit ?? 200, 1), 500);
  let start = 0;
  if (input.cursor) {
    const idx = names.findIndex((n) => n === input.cursor);
    start = idx >= 0 ? idx + 1 : 0;
  }

  const slice = names.slice(start, start + limit);
  const prepared: Array<{
    name: string;
    relativePath: string;
    isDirectory: boolean;
    sizeBytes: number;
    mtimeMs: number;
  }> = [];

  for (const name of slice) {
    const childAbs = path.join(abs, name);
    let childStat: fs.Stats;
    try {
      childStat = fs.lstatSync(childAbs);
    } catch {
      continue;
    }

    const rel = toPosixRelative(input.root.absolutePath, childAbs);
    prepared.push({
      name,
      relativePath: rel,
      isDirectory: childStat.isDirectory(),
      sizeBytes: childStat.isDirectory() ? 0 : childStat.size,
      mtimeMs: Math.floor(childStat.mtimeMs),
    });
  }

  const refs = await mintFileReferencesBatch(
    input.userId,
    input.root.id,
    prepared.map((p) => ({
      relativePath: p.relativePath,
      displayName: p.name,
      sizeBytes: p.sizeBytes,
      mtimeMs: p.mtimeMs,
    }))
  );

  const out: FileListEntry[] = prepared.map((p, i) => ({
    fileId: refs[i]!.id,
    name: p.name,
    relativePath: p.relativePath,
    isDirectory: p.isDirectory,
    sizeBytes: p.sizeBytes,
    mtimeMs: p.mtimeMs,
  }));

  const last = slice[slice.length - 1] ?? null;
  const nextCursor =
    last && start + slice.length < names.length ? last : null;

  return {
    entries: out,
    nextCursor,
    totalListed: names.length,
  };
}

export async function searchMetadata(input: {
  userId: string;
  roots: FileRootRecord[];
  filters: MetadataSearchFilters;
}): Promise<{ hits: FileSearchHit[]; filesScanned: number }> {
  const started = Date.now();
  const maxResults = input.filters.maxResults ?? SEARCH_MAX_RESULTS;
  const query = input.filters.query?.trim() ?? "";
  const extFilter = input.filters.extensions?.map((e) =>
    e.startsWith(".") ? e.toLowerCase() : `.${e.toLowerCase()}`
  );

  const scored: Array<FileSearchHit & { _score: number }> = [];
  let filesScanned = 0;

  for (const root of input.roots) {
    // BFS : privilégie les fichiers proches de la racine (docs perso avant Unity/…).
    const queue: Array<{ abs: string; depth: number }> = [
      { abs: root.absolutePath, depth: 0 },
    ];

    while (queue.length > 0) {
      if (Date.now() - started > WALK_TIMEOUT_MS) break;
      if (filesScanned >= WALK_MAX_FILES) break;

      const cur = queue.shift()!;
      let dirents: fs.Dirent[];
      try {
        dirents = fs.readdirSync(cur.abs, { withFileTypes: true });
      } catch {
        continue;
      }

      for (const ent of dirents) {
        if (Date.now() - started > WALK_TIMEOUT_MS) break;
        const childAbs = path.join(cur.abs, ent.name);
        let st: fs.Stats;
        try {
          st = fs.lstatSync(childAbs);
        } catch {
          continue;
        }
        if (st.isSymbolicLink()) continue;

        if (st.isDirectory()) {
          if (SEARCH_SKIP_DIR_NAMES.has(ent.name.toLowerCase())) continue;
          if (cur.depth < WALK_MAX_DEPTH) {
            queue.push({ abs: childAbs, depth: cur.depth + 1 });
          }
          continue;
        }

        filesScanned += 1;
        const ext = extensionOf(ent.name);
        if (extFilter && extFilter.length > 0 && !extFilter.includes(ext)) {
          continue;
        }
        if (
          input.filters.mtimeFromMs != null &&
          st.mtimeMs < input.filters.mtimeFromMs
        ) {
          continue;
        }
        if (
          input.filters.mtimeToMs != null &&
          st.mtimeMs > input.filters.mtimeToMs
        ) {
          continue;
        }
        if (input.filters.minSize != null && st.size < input.filters.minSize) {
          continue;
        }
        if (input.filters.maxSize != null && st.size > input.filters.maxSize) {
          continue;
        }

        const rel = toPosixRelative(root.absolutePath, childAbs);
        let score = query ? nameScore(`${ent.name} ${rel}`, query) : 10;
        if (query && score <= 0) continue;
        // Bonus fichiers peu profonds
        score += Math.max(0, 8 - cur.depth);

        // Mint différé : collecter d'abord, mint seulement le top-K après tri
        scored.push({
          fileId: "",
          filename: ent.name,
          relativePath: rel,
          rootId: root.id,
          sizeBytes: st.size,
          mtimeMs: Math.floor(st.mtimeMs),
          extension: ext,
          score,
          _score: score,
        });
      }
    }
  }

  scored.sort((a, b) => b._score - a._score || b.mtimeMs - a.mtimeMs);
  const strong = keepStrongSearchHits(
    scored.map((h) => ({ ...h, score: h._score })),
    { max: maxResults, minAbs: query ? 50 : 0, ratio: query ? 0.82 : 0 }
  );
  const top = strong.length > 0 ? strong : scored.slice(0, Math.min(3, maxResults));
  const minted = await Promise.all(
    top.map(async (hit) => {
      const ref = await mintFileReference({
        userId: input.userId,
        rootId: hit.rootId,
        relativePath: hit.relativePath,
        displayName: hit.filename,
        sizeBytes: hit.sizeBytes,
        mtimeMs: hit.mtimeMs,
      });
      return {
        ...hit,
        fileId: ref.id,
      };
    })
  );

  const hits = minted.map(({ _score: _, ...hit }) => {
    void _;
    return {
      ...hit,
      snippet: query
        ? hit.filename.slice(0, SEARCH_SNIPPET_MAX_CHARS)
        : undefined,
    };
  });

  return { hits, filesScanned };
}

export function readFileBounded(
  absolutePath: string,
  maxBytes: number
): Buffer {
  const st = fs.statSync(absolutePath);
  if (st.size > maxBytes) {
    const fd = fs.openSync(absolutePath, "r");
    try {
      const buf = Buffer.alloc(maxBytes);
      const read = fs.readSync(fd, buf, 0, maxBytes, 0);
      return buf.subarray(0, read);
    } finally {
      fs.closeSync(fd);
    }
  }
  return fs.readFileSync(absolutePath);
}

export function mkdirUnderRoot(
  rootAbsolute: string,
  relativePath: string
): string {
  const abs = resolveUnderRoot(rootAbsolute, relativePath);
  fs.mkdirSync(abs, { recursive: false });
  return abs;
}

export function renameUnderRoot(input: {
  rootAbsolute: string;
  sourceRelative: string;
  destRelative: string;
}): void {
  const src = resolveUnderRoot(input.rootAbsolute, input.sourceRelative);
  const dest = resolveUnderRoot(input.rootAbsolute, input.destRelative);
  if (fs.existsSync(dest)) {
    throw new Error("La destination existe déjà (overwrite=false).");
  }
  fs.renameSync(src, dest);
}

export function writeFileUnderRoot(input: {
  rootAbsolute: string;
  relativePath: string;
  data: Buffer;
  overwrite?: boolean;
}): string {
  const abs = resolveUnderRoot(input.rootAbsolute, input.relativePath);
  if (fs.existsSync(abs) && !input.overwrite) {
    throw new Error("Le fichier existe déjà (overwrite=false).");
  }
  const dir = path.dirname(abs);
  if (!fs.existsSync(dir)) {
    throw new Error("Le dossier destination n'existe pas.");
  }
  fs.writeFileSync(abs, input.data);
  return abs;
}

export function moveAcrossRoots(input: {
  sourceRootAbsolute: string;
  sourceRelative: string;
  destRootAbsolute: string;
  destRelative: string;
}): void {
  const src = resolveUnderRoot(input.sourceRootAbsolute, input.sourceRelative);
  const dest = resolveUnderRoot(input.destRootAbsolute, input.destRelative);
  if (fs.existsSync(dest)) {
    throw new Error("La destination existe déjà (overwrite=false).");
  }
  const destDir = path.dirname(dest);
  if (!fs.existsSync(destDir)) {
    throw new Error("Le dossier destination n'existe pas.");
  }
  fs.renameSync(src, dest);
}

/**
 * Supprime un fichier ou un dossier (récursif) sous la root.
 * Refuse de supprimer la racine elle-même.
 */
export function deleteFileUnderRoot(
  rootAbsolute: string,
  relativePath: string
): void {
  const rel = relativePath.replace(/\\/g, "/").replace(/^\/+|\/+$/g, "");
  if (!rel || rel === "." || rel === "..") {
    throw new Error("Impossible de supprimer la racine.");
  }
  const abs = resolveUnderRoot(rootAbsolute, rel);
  if (!fs.existsSync(abs)) {
    throw new Error("Chemin introuvable.");
  }
  const st = fs.lstatSync(abs);
  if (st.isDirectory()) {
    fs.rmSync(abs, { recursive: true, force: false });
    return;
  }
  fs.unlinkSync(abs);
}
