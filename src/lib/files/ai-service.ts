import { nanoid } from "nanoid";
import { getLocalAIRuntime } from "@/lib/runtime/factory";
import { getSettings } from "@/lib/settings/service";
import { listDirectory, searchMetadata, queryTokens } from "@/lib/files/provider";
import { searchFileIndexPassages } from "@/lib/files/index-service";
import { ensureDefaultRoots, getFileRoot, listEnabledFileRoots } from "@/lib/files/roots";
import { createFilesMutationAction } from "@/lib/files/mutations";
import { resolveFileReference } from "@/lib/files/resolve";
import { extractTextFromFile, guessMimeFromFilename } from "@/lib/documents/extract";
import { isFilesFeatureEnabled } from "@/lib/files/feature";
import { mintFileReference } from "@/lib/files/references";

const SEARCH_CARD_LIMIT = 4;
const SEARCH_CANDIDATE_LIMIT = 16;

function resolveModel(
  settings: Awaited<ReturnType<typeof getSettings>>,
  model?: string
): string {
  const resolved = model?.trim() || settings.selectedModel;
  if (!resolved) throw new Error("Aucun modèle sélectionné.");
  return resolved;
}

function responseText(response: unknown): string {
  if (!response || typeof response !== "object") return "";
  const r = response as {
    message?: { content?: unknown };
    choices?: Array<{ message?: { content?: unknown } }>;
    content?: unknown;
  };
  const raw =
    r.message?.content ??
    r.choices?.[0]?.message?.content ??
    r.content ??
    "";
  if (typeof raw === "string") return raw.trim();
  if (Array.isArray(raw)) {
    return raw
      .map((p) =>
        typeof p === "string"
          ? p
          : p && typeof p === "object" && "text" in p
            ? String((p as { text?: string }).text ?? "")
            : ""
      )
      .join("")
      .trim();
  }
  return String(raw ?? "").trim();
}

export type FilesAssistantAction =
  | "search"
  | "list"
  | "offer_file"
  | "analyze"
  | "create_directory"
  | "save_upload"
  | "chat";

export type FilesAssistantFileCard = {
  fileId: string;
  name: string;
  relativePath: string;
  rootId: string;
  isDirectory: boolean;
  sizeBytes?: number;
  snippet?: string;
};

export type FilesAssistantMutation = {
  actionId: string;
  confirmationToken: string;
  expiresAt: string;
  op: "create_directory" | "rename_file" | "move_file";
  payload: {
    sourceRelativePath?: string;
    destRootId: string;
    destRelativePath: string;
  };
};

/** Proposition d'enregistrement de fichiers collés / déposés (pas encore sur disque). */
export type FilesAssistantUploadProposal = {
  destRootId: string;
  /** Dossier destination relatif ("" = racine de la source). */
  destRelativePath: string;
  fileNames: string[];
};

type Intent = {
  action: FilesAssistantAction;
  query: string | null;
  /** Variantes de recherche proposées par l'IA (pas de synonymes hardcodés). */
  queries: string[];
  folderName: string | null;
  /** Dossier parent relatif pour create_directory (ex. "Identité"). */
  parentPath: string | null;
  searchAllRoots: boolean;
  reason: string;
};

const ALLOWED_ACTIONS: FilesAssistantAction[] = [
  "search",
  "list",
  "offer_file",
  "analyze",
  "create_directory",
  "save_upload",
  "chat",
];

function parseIntent(raw: string): Intent | null {
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    const obj = JSON.parse(raw.slice(start, end + 1)) as Record<string, unknown>;
    const action = String(obj.action ?? "chat") as FilesAssistantAction;
    if (!ALLOWED_ACTIONS.includes(action)) return null;
    const query =
      typeof obj.query === "string" ? obj.query.trim() || null : null;
    const queries: string[] = [];
    if (Array.isArray(obj.queries)) {
      for (const q of obj.queries) {
        if (typeof q === "string" && q.trim()) queries.push(q.trim());
      }
    }
    if (query && !queries.includes(query)) queries.unshift(query);
    return {
      action,
      query,
      queries: queries.slice(0, 6),
      folderName:
        typeof obj.folderName === "string"
          ? obj.folderName.trim().replace(/[\\/]/g, "") || null
          : null,
      parentPath:
        typeof obj.parentPath === "string"
          ? obj.parentPath
              .trim()
              .replace(/\\/g, "/")
              .replace(/^\/+|\/+$/g, "")
          : null,
      searchAllRoots:
        typeof obj.searchAllRoots === "boolean"
          ? obj.searchAllRoots
          : action === "search" || action === "offer_file",
      reason: typeof obj.reason === "string" ? obj.reason : "ok",
    };
  } catch {
    return null;
  }
}

/**
 * Première passe IA : analyse sémantique du message (aucune détection par mots-clés).
 */
async function classifyIntent(input: {
  message: string;
  model?: string;
  currentPath: string;
  selectedNames: string[];
  rootLabel: string;
  pendingUploads?: Array<{ name: string; sizeBytes: number }>;
}): Promise<Intent> {
  const settings = await getSettings();
  const runtime = getLocalAIRuntime();
  const model = resolveModel(settings, input.model);
  const pendingNote =
    input.pendingUploads && input.pendingUploads.length > 0
      ? `\nFichiers NOUVEAUX collés/déposés (pas encore enregistrés sur le disque) : ${input.pendingUploads
          .map((f) => f.name)
          .join(", ")}.
IMPORTANT: ces fichiers n'existent pas encore. N'utilise JAMAIS search/offer_file/analyze pour eux. action=save_upload obligatoirement.
parentPath = dossier destination relatif demandé ("" si racine de la source ; chemin relatif sinon ; null = dossier courant).`
      : "";
  const system = `Tu analyses une demande dans un gestionnaire de fichiers local.
Sortie = UN objet JSON, rien d'autre.
{"action":"search|list|offer_file|analyze|create_directory|save_upload|chat","query":string|null,"queries":string[],"folderName":string|null,"parentPath":string|null,"searchAllRoots":bool,"reason":"court"}
Actions:
- search: chercher des fichiers (plusieurs résultats possibles)
- offer_file: trouver / donner un fichier précis DÉJÀ présent sur le disque à ouvrir
- list: lister le dossier courant
- analyze: analyser/résumer un fichier (sélectionné ou à trouver via query)
- create_directory: créer un dossier
  - folderName = nom du NOUVEAU dossier uniquement (pas le chemin). Si l'utilisateur ne donne pas de nom → null
  - parentPath = dossier PARENT relatif où le créer (ex. "Identité", "Travail/2024"). Si non précisé → null (= dossier courant)
  Exemple: « crée un dossier Archives dans Identité » → folderName="Archives", parentPath="Identité"
  Exemple: « crée un dossier dans identité/ » → folderName=null, parentPath="identité"
- save_upload: enregistrer des fichiers collés/déposés (nouveaux) quelque part
  - parentPath = destination ("" ou "/" = racine de la source ; "Identité" = ce dossier ; null = dossier courant)
  - Exemple: « enregistre à la racine » → parentPath=""
  - Exemple: « mets ça dans Identité » → parentPath="Identité"
  - N'utilise PAS search : un homonyme ailleurs n'est PAS le fichier collé
- chat: question générale sans outil fichier
query = termes de recherche principaux (si search/offer_file/analyze).
queries = 1 à 5 variantes utiles pour le moteur de recherche (abréviations, orthographes, extensions) — inventées selon le sens, pas une liste fixe.
searchAllRoots=true si la recherche doit couvrir toutes les sources (Documents, Downloads…), sinon false (source courante seulement).
Contexte: source="${input.rootLabel}" path="${input.currentPath || "/"}" sélection=[${input.selectedNames.join(", ") || "aucune"}]${pendingNote}`;

  const run = async (sys: string) => {
    const response = await runtime.chat({
      requestId: nanoid(),
      model,
      messages: [
        { role: "system", content: sys },
        { role: "user", content: input.message },
      ],
      temperature: 0,
      maxTokens: 768,
      reasoningEffort: "none",
    });
    return parseIntent(responseText(response));
  };

  let resolved = await run(system);
  if (!resolved) {
    resolved = await run(
      input.pendingUploads?.length
        ? 'JSON only: {"action":"save_upload","query":null,"queries":[],"folderName":null,"parentPath":null,"searchAllRoots":false,"reason":"upload"}'
        : 'JSON only: {"action":"search","query":"...","queries":["..."],"folderName":null,"parentPath":null,"searchAllRoots":true,"reason":"x"}'
    );
  }

  if (!resolved) {
    console.warn("[files/intent] échec analyse:", input.message.slice(0, 120));
    return {
      action: input.pendingUploads?.length ? "save_upload" : "chat",
      query: null,
      queries: [],
      folderName: null,
      parentPath: null,
      searchAllRoots: false,
      reason: "Analyse d'intention indisponible",
    };
  }

  if (
    input.pendingUploads &&
    input.pendingUploads.length > 0 &&
    (resolved.action === "search" ||
      resolved.action === "offer_file" ||
      resolved.action === "analyze" ||
      resolved.action === "list")
  ) {
    resolved = {
      ...resolved,
      action: "save_upload",
      reason: "forced_save_upload",
    };
  }

  return { ...resolved, reason: resolved.reason || "Analyse IA" };
}

function normalizePathKey(s: string): string {
  return s
    .normalize("NFD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/\\/g, "/")
    .replace(/^\/+|\/+$/g, "");
}

/**
 * Résout un parentPath hint (ex. "identité") vers un chemin réel sous la root.
 * Priorité : chemin exact → match insensible à la casse dans le dossier courant → à la racine.
 */
async function resolveParentPath(input: {
  userId: string;
  root: NonNullable<Awaited<ReturnType<typeof getFileRoot>>>;
  hint: string | null;
  currentPath: string;
}): Promise<string> {
  const hint = (input.hint ?? "").trim().replace(/\\/g, "/").replace(/^\/+|\/+$/g, "");
  if (!hint || hint === "." || hint === "./") {
    return input.currentPath;
  }

  const tryExact = async (rel: string): Promise<string | null> => {
    try {
      await listDirectory({
        userId: input.userId,
        root: input.root,
        relativePath: rel,
        limit: 1,
      });
      return rel;
    } catch {
      return null;
    }
  };

  const exact = await tryExact(hint);
  if (exact != null) return exact;

  const findChild = async (parent: string, nameHint: string) => {
    try {
      const listed = await listDirectory({
        userId: input.userId,
        root: input.root,
        relativePath: parent,
        limit: 500,
      });
      const key = normalizePathKey(nameHint);
      const hit = listed.entries.find(
        (e) => e.isDirectory && normalizePathKey(e.name) === key
      );
      return hit?.relativePath ?? null;
    } catch {
      return null;
    }
  };

  // Hint multi-segments : résoudre segment par segment depuis la racine.
  const parts = hint.split("/").filter(Boolean);
  let cursor = "";
  for (const part of parts) {
    const next = await findChild(cursor, part);
    if (!next) {
      // Segment inconnu : garder le hint tel quel (mkdir créera les parents? non — mkdirUnderRoot?)
      return hint;
    }
    cursor = next;
  }
  if (cursor) return cursor;

  // Match dans le dossier courant puis à la racine
  const inCurrent = await findChild(input.currentPath, hint);
  if (inCurrent) return inCurrent;
  const inRoot = await findChild("", hint);
  if (inRoot) return inRoot;

  return hint;
}

async function collectSearchHits(input: {
  userId: string;
  root: NonNullable<Awaited<ReturnType<typeof getFileRoot>>>;
  roots: NonNullable<Awaited<ReturnType<typeof getFileRoot>>>[];
  queries: string[];
}): Promise<FilesAssistantFileCard[]> {
  const queries = input.queries.map((q) => q.trim()).filter(Boolean);
  if (queries.length === 0) return [];

  const byId = new Map<string, FilesAssistantFileCard & { _score: number }>();

  const runQueries = async (qs: string[], scoreBoost = 0) => {
    for (const q of qs) {
      const { hits } = await searchMetadata({
        userId: input.userId,
        roots: input.roots,
        filters: { query: q, maxResults: SEARCH_CANDIDATE_LIMIT },
      });
      for (const h of hits) {
        const prev = byId.get(h.fileId);
        const score = (h.score ?? 0) + scoreBoost;
        if (!prev || score > prev._score) {
          byId.set(h.fileId, {
            fileId: h.fileId,
            name: h.filename,
            relativePath: h.relativePath,
            rootId: h.rootId,
            isDirectory: false,
            sizeBytes: h.sizeBytes,
            snippet: h.snippet,
            _score: score,
          });
        }
      }
    }
  };

  await runQueries(queries);

  // Fallback tokens seuls UNIQUEMENT si zéro hit (sinon « carte » seul pollue les résultats).
  if (byId.size === 0) {
    const tokenSet = new Set<string>();
    for (const q of queries) {
      for (const t of queryTokens(q)) {
        if (t.length >= 3) tokenSet.add(t);
      }
    }
    const tokenQueries = [...tokenSet].slice(0, 8);
    if (tokenQueries.length > 0) {
      await runQueries(tokenQueries, -5);
    }
  }

  if (byId.size < 4 && input.root) {
    const primary = queries[0]!;
    try {
      const passages = await searchFileIndexPassages({
        userId: input.userId,
        rootId: input.root.id,
        query: primary,
        limit: 8,
      });
      for (const p of passages) {
        const name = p.relativePath.split("/").pop() ?? p.relativePath;
        const ref = await mintFileReference({
          userId: input.userId,
          rootId: input.root.id,
          relativePath: p.relativePath,
          displayName: name,
          sizeBytes: 0,
          mtimeMs: Date.now(),
        });
        if (byId.has(ref.id)) continue;
        byId.set(ref.id, {
          fileId: ref.id,
          name,
          relativePath: p.relativePath,
          rootId: input.root.id,
          isDirectory: false,
          snippet: p.content.slice(0, 140),
          _score: 40,
        });
      }
    } catch {
      /* index optional */
    }
  }

  return [...byId.values()]
    .sort((a, b) => b._score - a._score)
    .slice(0, SEARCH_CANDIDATE_LIMIT)
    .map(({ _score: _, ...rest }) => {
      void _;
      return rest;
    });
}

async function refineSearchWithLlm(input: {
  message: string;
  query: string;
  candidates: FilesAssistantFileCard[];
  model: string;
  offer: boolean;
}): Promise<{ reply: string; files: FilesAssistantFileCard[] }> {
  if (input.candidates.length === 0) {
    return {
      reply: `Je n’ai trouvé aucun fichier correspondant à « ${input.query} ». Reformule ou précise le nom / l’extension.`,
      files: [],
    };
  }

  const runtime = getLocalAIRuntime();
  const catalog = input.candidates
    .map(
      (f, i) =>
        `${i + 1}. id=${f.fileId} | ${f.name} | ${f.relativePath}${
          f.snippet ? ` | ${f.snippet.slice(0, 80)}` : ""
        }`
    )
    .join("\n");

  const system = `Tu es l'assistant Files. L'utilisateur cherche un fichier.
Choisis UNIQUEMENT les fichiers vraiment pertinents (max ${SEARCH_CARD_LIMIT}).
Écarte les faux positifs hors sujet.
Réponds UNIQUEMENT en JSON:
{"fileIds":["..."],"reply":"phrase courte en français"}
- fileIds: 0 à ${SEARCH_CARD_LIMIT} ids de la liste (vide si rien de pertinent)
- reply: explique brièvement
Demande utilisateur: « ${input.message} »
Requête: « ${input.query} »
Candidats:
${catalog}`;

  const response = await runtime.chat({
    requestId: nanoid(),
    model: input.model,
    messages: [
      { role: "system", content: system },
      { role: "user", content: input.message },
    ],
    temperature: 0,
    maxTokens: 512,
    reasoningEffort: "none",
  });

  const raw = responseText(response);
  const start = raw.indexOf("{");
  const end = raw.lastIndexOf("}");
  let pickedIds: string[] = [];
  let reply = "";
  if (start >= 0 && end > start) {
    try {
      const obj = JSON.parse(raw.slice(start, end + 1)) as {
        fileIds?: unknown;
        reply?: unknown;
      };
      if (Array.isArray(obj.fileIds)) {
        pickedIds = obj.fileIds
          .map((x) => String(x))
          .filter((id) => input.candidates.some((c) => c.fileId === id))
          .slice(0, SEARCH_CARD_LIMIT);
      }
      if (typeof obj.reply === "string") reply = obj.reply.trim();
    } catch {
      /* fallback */
    }
  }

  if (pickedIds.length === 0) {
    // Dernier recours structurel (pas lexical) : tous les tokens significatifs du query dans le nom/chemin
    const primaryTokens = queryTokens(input.query);
    const strong = input.candidates
      .filter((c) => {
        if (primaryTokens.length === 0) return false;
        const hay = `${c.name} ${c.relativePath}`
          .normalize("NFD")
          .replace(/\p{M}/gu, "")
          .toLowerCase();
        return primaryTokens.every((t) => hay.includes(t));
      })
      .slice(0, input.offer ? 2 : SEARCH_CARD_LIMIT);

    if (strong.length > 0) {
      return {
        reply:
          reply ||
          `Voici ${strong.length > 1 ? "les fichiers" : "le fichier"} correspondant${strong.length > 1 ? "s" : ""} :`,
        files: strong,
      };
    }

    return {
      reply:
        reply ||
        `Je n’ai pas identifié de fichier convaincant pour « ${input.query} ».`,
      files: [],
    };
  }

  const files = pickedIds
    .map((id) => input.candidates.find((c) => c.fileId === id)!)
    .filter(Boolean);

  return {
    reply:
      reply ||
      (files.length === 1
        ? "Voici le fichier le plus probable :"
        : `Voici ${files.length} fichiers pertinents :`),
    files,
  };
}

async function ensureWorkspaceConversation(userId: string): Promise<string> {
  const { getDb } = await import("@/lib/db");
  const { conversations } = await import("@/lib/db/schema");
  const { eq } = await import("drizzle-orm");
  const id = `files-workspace:${userId}`;
  const db = getDb();
  const existing = await db.query.conversations.findFirst({
    where: eq(conversations.id, id),
  });
  if (!existing) {
    await db.insert(conversations).values({
      id,
      title: "Files workspace",
      titleSource: "user",
    });
  }
  return id;
}

function searchQueriesFromIntent(intent: Intent, fallbackMessage: string): string[] {
  const qs = [...intent.queries];
  if (intent.query && !qs.includes(intent.query)) qs.unshift(intent.query);
  if (qs.length === 0 && fallbackMessage.trim()) qs.push(fallbackMessage.trim());
  return qs.slice(0, 6);
}

export async function filesAssistantChat(input: {
  userId: string;
  message: string;
  rootId: string;
  currentPath?: string;
  selectedFileIds?: string[];
  model?: string;
  pendingUploads?: Array<{ name: string; sizeBytes: number }>;
}): Promise<{
  reply: string;
  files: FilesAssistantFileCard[];
  mutation?: FilesAssistantMutation;
  uploadProposal?: FilesAssistantUploadProposal;
  action: FilesAssistantAction;
}> {
  if (!isFilesFeatureEnabled()) {
    throw new Error("Files désactivé.");
  }

  await ensureDefaultRoots(input.userId);
  const root = await getFileRoot(input.userId, input.rootId);
  if (!root?.enabled) throw new Error("Root invalide.");

  const currentPath = (input.currentPath ?? "").replace(/\\/g, "/");
  const selectedIds = input.selectedFileIds ?? [];
  const selectedMeta: FilesAssistantFileCard[] = [];
  for (const id of selectedIds.slice(0, 8)) {
    try {
      const r = await resolveFileReference(input.userId, id);
      selectedMeta.push({
        fileId: r.fileId,
        name: r.displayName,
        relativePath: r.relativePath,
        rootId: r.rootId,
        isDirectory: r.isDirectory,
        sizeBytes: r.sizeBytes,
      });
    } catch {
      /* ignore stale ids */
    }
  }

  let intent = await classifyIntent({
    message: input.message,
    model: input.model,
    currentPath,
    selectedNames: selectedMeta.map((s) => s.name),
    rootLabel: root.label,
    pendingUploads: input.pendingUploads,
  });

  const settings = await getSettings();
  const runtime = getLocalAIRuntime();
  const model = resolveModel(settings, input.model);
  let files: FilesAssistantFileCard[] = [];
  let mutation: FilesAssistantMutation | undefined;
  let uploadProposal: FilesAssistantUploadProposal | undefined;
  let toolContext = "";

  if (
    (input.pendingUploads?.length ?? 0) > 0 &&
    intent.action !== "save_upload"
  ) {
    intent = { ...intent, action: "save_upload" };
  }

  if (intent.action === "save_upload") {
    const pending = input.pendingUploads ?? [];
    const fileNames = pending.map((f) => f.name);
    const hintRaw = intent.parentPath;
    const msgNorm = input.message
      .normalize("NFD")
      .replace(/\p{M}/gu, "")
      .toLowerCase();
    const wantsRoot =
      hintRaw === "" ||
      hintRaw === "/" ||
      (typeof hintRaw === "string" &&
        /^(racine|root|\.)$/i.test(hintRaw.trim())) ||
      (hintRaw == null && /\b(a la )?racine\b|\bat root\b/.test(msgNorm));

    let destDir = currentPath;
    if (wantsRoot) {
      destDir = "";
    } else if (hintRaw != null && hintRaw !== "") {
      destDir = await resolveParentPath({
        userId: input.userId,
        root,
        hint: hintRaw,
        currentPath,
      });
    }

    // Collision uniquement dans le dossier cible (pas un homonyme ailleurs)
    const collisions: string[] = [];
    try {
      const listed = await listDirectory({
        userId: input.userId,
        root,
        relativePath: destDir,
        limit: 500,
      });
      const existing = new Set(
        listed.entries
          .filter((e) => !e.isDirectory)
          .map((e) => e.name.toLowerCase())
      );
      for (const name of fileNames) {
        if (existing.has(name.toLowerCase())) collisions.push(name);
      }
    } catch {
      /* dossier cible inexistant → pas de collision */
    }

    uploadProposal = {
      destRootId: root.id,
      destRelativePath: destDir,
      fileNames,
    };

    const destLabel = destDir ? destDir : `la racine de ${root.label}`;
    const namesLabel =
      fileNames.length > 0
        ? fileNames.map((n) => `« ${n} »`).join(", ")
        : "le(s) fichier(s)";
    let reply = `Je propose d’enregistrer ${namesLabel} dans ${destLabel}. Vérifie la destination dans la boîte de dialogue, puis confirme.`;
    if (collisions.length > 0) {
      reply += ` Attention : ${collisions
        .map((n) => `« ${n} »`)
        .join(", ")} existe déjà à cet emplacement — l’enregistrement peut échouer ou écraser selon les options.`;
    }

    return {
      reply,
      files: [],
      uploadProposal,
      action: "save_upload",
    };
  }

  if (intent.action === "list") {
    const listed = await listDirectory({
      userId: input.userId,
      root,
      relativePath: currentPath,
      limit: 40,
    });
    files = listed.entries.slice(0, 20).map((e) => ({
      fileId: e.fileId,
      name: e.name,
      relativePath: e.relativePath,
      rootId: root.id,
      isDirectory: e.isDirectory,
      sizeBytes: e.sizeBytes,
    }));
    toolContext = `Contenu de "${currentPath || root.label}" (${listed.totalListed} éléments):\n${files
      .map((f) => `- ${f.isDirectory ? "[dir]" : "[file]"} ${f.name}`)
      .join("\n")}`;
  } else if (intent.action === "search" || intent.action === "offer_file") {
    const queries = searchQueriesFromIntent(intent, input.message);
    const allRoots = await listEnabledFileRoots(input.userId);
    const searchRoots = intent.searchAllRoots
      ? allRoots.length > 0
        ? allRoots
        : [root]
      : [root];
    const candidates = await collectSearchHits({
      userId: input.userId,
      root,
      roots: searchRoots,
      queries,
    });
    const refined = await refineSearchWithLlm({
      message: input.message,
      query: queries[0] ?? input.message,
      candidates,
      model,
      offer: intent.action === "offer_file",
    });
    return {
      reply: refined.reply,
      files: refined.files,
      action: intent.action,
    };
  } else if (intent.action === "analyze") {
    let target = selectedMeta[0];
    if (!target) {
      const queries = searchQueriesFromIntent(intent, input.message);
      const allRoots = await listEnabledFileRoots(input.userId);
      const candidates = await collectSearchHits({
        userId: input.userId,
        root,
        roots: allRoots.length > 0 ? allRoots : [root],
        queries,
      });
      const refined = await refineSearchWithLlm({
        message: input.message,
        query: queries[0] ?? input.message,
        candidates,
        model,
        offer: true,
      });
      target = refined.files[0];
      if (!target) {
        return {
          reply:
            refined.reply ||
            "Aucun fichier à analyser. Sélectionne un fichier ou précise son nom.",
          files: [],
          action: intent.action,
        };
      }
    }
    if (target && !target.isDirectory) {
      files = [target];
      try {
        const resolved = await resolveFileReference(input.userId, target.fileId);
        const mime =
          guessMimeFromFilename(resolved.displayName) ||
          "application/octet-stream";
        const text = await extractTextFromFile(
          resolved.absolutePath,
          mime,
          resolved.displayName
        );
        const SMALL_DOC_CHARS = 8000;
        const query =
          intent.queries?.[0] ||
          input.message ||
          resolved.displayName;
        if (text.length <= SMALL_DOC_CHARS) {
          toolContext = `Fichier ${resolved.displayName} (${resolved.relativePath}):\n${text}`;
        } else {
          const passages = await searchFileIndexPassages({
            userId: input.userId,
            rootId: resolved.rootId,
            relativePath: resolved.relativePath,
            query,
            limit: 6,
          });
          if (passages.length > 0) {
            toolContext = `Fichier ${resolved.displayName} (${resolved.relativePath}) — passages pertinents:\n${passages
              .map((p, i) => `[${i + 1}] ${p.content}`)
              .join("\n\n")}`;
          } else {
            // Index miss: fall back to head+tail, not head-only
            const head = text.slice(0, 3500);
            const tail = text.slice(-2500);
            toolContext = `Fichier ${resolved.displayName} (${resolved.relativePath}) — extrait début+fin (index indisponible):\n${head}\n\n…\n\n${tail}`;
          }
        }
      } catch (err) {
        toolContext = `Impossible d'extraire ${target.name}: ${
          err instanceof Error ? err.message : "erreur"
        }`;
      }
    } else {
      toolContext = "Aucun fichier sélectionné à analyser.";
    }
  } else if (intent.action === "create_directory") {
    const name = (intent.folderName || "Nouveau dossier")
      .replace(/[\\/]/g, "")
      .trim();
    const parent = await resolveParentPath({
      userId: input.userId,
      root,
      hint: intent.parentPath,
      currentPath,
    });
    const destRelativePath = parent ? `${parent}/${name}` : name;
    const conversationId = await ensureWorkspaceConversation(input.userId);
    const proposed = await createFilesMutationAction({
      userId: input.userId,
      conversationId,
      actionType: "create_directory",
      payload: {
        op: "create_directory",
        destRootId: root.id,
        destRelativePath,
        overwrite: false,
      },
    });
    mutation = {
      actionId: proposed.actionId,
      confirmationToken: proposed.confirmationToken,
      expiresAt: proposed.expiresAt,
      op: "create_directory",
      payload: {
        destRootId: proposed.payload.destRootId,
        destRelativePath: proposed.payload.destRelativePath,
      },
    };
    const parentLabel = parent || root.label;
    return {
      reply: intent.folderName
        ? `Je propose de créer « ${name} » dans ${parentLabel}. Tu peux ajuster le nom ou la destination ci-dessous, puis confirmer.`
        : `Je propose de créer un dossier dans ${parentLabel}. Choisis un nom et vérifie la destination ci-dessous, puis confirme.`,
      files: [],
      mutation,
      action: intent.action,
    };
  } else {
    // chat — contexte léger du dossier (pas une détection d'intent)
    try {
      const listed = await listDirectory({
        userId: input.userId,
        root,
        relativePath: currentPath,
        limit: 25,
      });
      files = listed.entries.slice(0, 6).map((e) => ({
        fileId: e.fileId,
        name: e.name,
        relativePath: e.relativePath,
        rootId: root.id,
        isDirectory: e.isDirectory,
        sizeBytes: e.sizeBytes,
      }));
      toolContext = `Dossier courant "${currentPath || root.label}":\n${listed.entries
        .slice(0, 20)
        .map((e) => `- ${e.isDirectory ? "[dir]" : "[file]"} ${e.name}`)
        .join("\n")}`;
    } catch {
      toolContext = `Root: ${root.label}`;
    }
  }

  const replySystem = `Tu es l'assistant Files d'un Personal AI Assistant local.
Réponds en français, concis et utile. Tu ne cites jamais de chemins absolus Windows.
Si des fileId sont fournis, invite l'utilisateur à cliquer les cartes fichier dans l'UI.
Si une confirmation de mutation est en attente, explique clairement qu'il faut confirmer.
Contexte outil:\n${toolContext || "(aucun)"}`;

  const replyRes = await runtime.chat({
    requestId: nanoid(),
    model,
    messages: [
      { role: "system", content: replySystem },
      { role: "user", content: input.message },
    ],
    temperature: 0.3,
    maxTokens: 1024,
    reasoningEffort: "none",
  });

  let reply = responseText(replyRes);
  if (!reply) {
    if (files.length > 0) {
      if (intent.action === "list") {
        reply = `Voici ${files.length} élément${files.length > 1 ? "s" : ""} dans ce dossier :`;
      } else if (intent.action === "chat") {
        reply = "Voici un aperçu du dossier courant :";
      } else {
        reply = `J’ai trouvé ${files.length} résultat${files.length > 1 ? "s" : ""}.`;
      }
    } else if (mutation) {
      reply = "Proposition prête — confirme l’action ci-dessous.";
    } else if (intent.action === "list") {
      reply = "Ce dossier est vide.";
    } else {
      reply = "Je n’ai pas trouvé de résultat pour cette demande.";
    }
  }

  return {
    reply,
    files,
    mutation,
    action: intent.action,
  };
}
