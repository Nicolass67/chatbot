import type { FileIntent } from "@/lib/request-router/types";

export interface FilesHandoffParams {
  intent: FileIntent;
  query?: string;
  rootId?: string;
}

export interface FilesHandoffRef {
  intent: FileIntent;
  query?: string;
  rootId?: string;
  reason: string;
}

export interface FilesHandoffResult extends FilesHandoffRef {
  /** @deprecated Dérivé Web Next — préférer IDs + resolveFilesHandoffHref */
  url: string;
}

const ROOT_ID_PATTERN = /^[a-zA-Z0-9_-]{8,40}$/;
const INTENT_SET = new Set<FileIntent>([
  "none",
  "search",
  "list",
  "read",
  "analyze",
  "organize",
]);

function sanitizeQuery(query: string | undefined): string | undefined {
  if (!query?.trim()) return undefined;
  return query.trim().slice(0, 500).replace(/[<>"'`\\]/g, "");
}

function sanitizeRootId(rootId: string | undefined): string | undefined {
  if (!rootId?.trim()) return undefined;
  const trimmed = rootId.trim();
  return ROOT_ID_PATTERN.test(trimmed) ? trimmed : undefined;
}

function sanitizeIntent(intent: FileIntent): FileIntent {
  return INTENT_SET.has(intent) ? intent : "none";
}

/** Path Web `/files…` depuis la référence métier. */
export function resolveFilesHandoffHref(ref: {
  intent: FileIntent;
  query?: string;
  rootId?: string;
}): string {
  const intent = sanitizeIntent(ref.intent);
  const query = sanitizeQuery(ref.query);
  const rootId = sanitizeRootId(ref.rootId);

  const sp = new URLSearchParams();
  if (intent !== "none") sp.set("intent", intent);
  if (query) sp.set("q", query);
  if (rootId) sp.set("root", rootId);

  const qs = sp.toString();
  return qs ? `/files?${qs}` : "/files";
}

/** Construit une référence Files — le LLM ne forge pas l'URL librement. */
export function buildFilesHandoffUrl(
  params: FilesHandoffParams
): FilesHandoffResult {
  const intent = sanitizeIntent(params.intent);
  const query = sanitizeQuery(params.query);
  const rootId = sanitizeRootId(params.rootId);

  const reason =
    intent === "search"
      ? "Recherche fichiers demandée."
      : "Ouverture de l'espace Files.";

  const ref: FilesHandoffRef = { intent, query, rootId, reason };
  return {
    ...ref,
    url: resolveFilesHandoffHref(ref),
  };
}

export function handoffMessageForFilesIntent(intent: FileIntent): string {
  switch (intent) {
    case "search":
      return "Je vous oriente vers Files pour affiner la recherche.";
    case "list":
      return "Je vous oriente vers Files pour parcourir vos dossiers.";
    case "analyze":
      return "Je vous oriente vers Files pour analyser le document.";
    case "organize":
      return "Je vous oriente vers Files pour organiser vos documents.";
    default:
      return "Consultez la section Files pour gérer vos documents locaux.";
  }
}
