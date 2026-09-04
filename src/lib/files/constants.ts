/** Limites par opération — pas un plafond unique universel. */

export const FILE_REF_TTL_MS = 2 * 60 * 60 * 1000; // 2h

export const SEARCH_SNIPPET_MAX_CHARS = 200;
export const SEARCH_MAX_RESULTS = 25;

export const WALK_MAX_FILES = 8000;
export const WALK_MAX_DEPTH = 8;
export const WALK_TIMEOUT_MS = 12_000;

/** Dossiers à ignorer pendant la recherche (bruit Unity/Unreal/npm…). */
export const SEARCH_SKIP_DIR_NAMES = new Set([
  "node_modules",
  ".git",
  ".svn",
  ".hg",
  "__pycache__",
  ".cache",
  ".vs",
  ".idea",
  "library",
  "intermediate",
  "saved",
  "binaries",
  "deriveddatacache",
  "shadercache",
  "vendor",
  "dist",
  "build",
  "obj",
  "packages",
  "temp",
  "tmp",
  "intermediates",
  ".gradle",
  ".nuget",
  "logs",
]);

export const LIMITS = {
  textExtractBytes: 10 * 1024 * 1024,
  pdfBytes: 25 * 1024 * 1024,
  officeBytes: 20 * 1024 * 1024,
  imageVisionBytes: 12 * 1024 * 1024,
  analyzeMaxChars: 12_000,
  readDefaultMaxChars: 8_000,
  indexMaxFileBytes: 20 * 1024 * 1024,
} as const;

export const DEFAULT_ROOT_LABELS = {
  documents: "Documents",
  downloads: "Downloads",
} as const;

/** Patterns sensibles : jamais exposés au LLM / jamais indexés en contenu. */
export const SENSITIVE_NAME_PATTERNS: RegExp[] = [
  /^\.env(\..+)?$/i,
  /^\.ssh$/i,
  /^id_rsa/i,
  /^id_ed25519/i,
  /^id_ecdsa/i,
  /\.pem$/i,
  /\.key$/i,
  /\.p12$/i,
  /\.pfx$/i,
  /^credentials(\.json)?$/i,
  /^secrets?(\.json|\.ya?ml)?$/i,
  /^token(s)?(\.json)?$/i,
  /^\.aws$/i,
  /^\.gnupg$/i,
  /^cookies?(\.sqlite|\.txt)?$/i,
  /^login data$/i,
];

export const SENSITIVE_PATH_SEGMENT_PATTERNS: RegExp[] = [
  /(^|\/|\\)\.ssh(\/|\\|$)/i,
  /(^|\/|\\)\.aws(\/|\\|$)/i,
  /(^|\/|\\)\.gnupg(\/|\\|$)/i,
  /(^|\/|\\)credentials(\/|\\|$)/i,
];

export const INDEXABLE_EXTENSIONS = new Set([
  ".txt",
  ".md",
  ".markdown",
  ".csv",
  ".json",
  ".pdf",
  ".docx",
  ".xlsx",
]);

export const IMAGE_EXTENSIONS = new Set([
  ".jpg",
  ".jpeg",
  ".png",
  ".webp",
]);
