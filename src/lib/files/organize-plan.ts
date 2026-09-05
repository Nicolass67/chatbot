import { nanoid } from "nanoid";
import { getLocalAIRuntime } from "@/lib/runtime/factory";
import { getSettings } from "@/lib/settings/service";

export type OrganizePlanItem = {
  name?: string;
  relativePath?: string;
  isDirectory?: boolean;
  extension?: string;
  sizeBytes?: number;
  parentRelativePath?: string;
  depth?: number;
  fileId?: string;
  mtimeMs?: number;
};

export type OrganizePlanMove = {
  source: string;
  destination: string;
  confidence: number;
  reason: string;
};

export type OrganizePlanResult = {
  summary: string;
  proposedDirectories: string[];
  moves: OrganizePlanMove[];
  warnings: string[];
};

const SYSTEM_PROMPT = `Tu es un planificateur d'organisation de fichiers pour une app iPhone.
Réponds UNIQUEMENT avec un JSON valide, sans markdown, sans commentaire.
Schéma strict:
{
  "summary": string,
  "proposedDirectories": string[],
  "moves": [{"source": string, "destination": string, "confidence": number, "reason": string}],
  "warnings": string[]
}
Règles:
- Ne jamais proposer de suppression.
- Ne jamais toucher aux chemins listés dans protectedPaths (ni leurs enfants).
- Ne déplacer que des fichiers déjà à la racine du dossier scope (pas déjà imbriqués).
- confidence entre 0 et 1 ( >= 0.72 pour exécution auto).
- destination = chemin relatif complet sous la root (ex. "Factures/invoice.pdf").
- proposedDirectories = dossiers parents à créer (chemins relatifs).
- Préfère des dossiers clairs: Factures, Contrats, Images, Voyages, A classer.
- Si l'instruction utilisateur est fournie, respecte-la en priorité sans casser les protections.`;

function responseText(response: { content?: string }): string {
  return (response.content ?? "").trim();
}

function extractJsonObject(raw: string): unknown {
  const trimmed = raw.trim();
  if (trimmed.startsWith("{")) {
    return JSON.parse(trimmed);
  }
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start >= 0 && end > start) {
    return JSON.parse(trimmed.slice(start, end + 1));
  }
  throw new Error("JSON introuvable dans la réponse modèle");
}

function clampConfidence(value: unknown): number {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return 0.5;
  return Math.max(0, Math.min(1, n));
}

export async function generateOrganizePlan(params: {
  rootId: string;
  rootRelativePath: string;
  items: OrganizePlanItem[];
  protectedPaths: string[];
  instruction?: string | null;
}): Promise<OrganizePlanResult> {
  const settings = await getSettings();
  const model = settings.selectedModel?.trim();
  if (!model) {
    const err = new Error("Aucun modèle sélectionné pour l’organisation.");
    (err as Error & { code?: string }).code = "MODEL_UNAVAILABLE";
    throw err;
  }

  const runtime = getLocalAIRuntime();
  try {
    await runtime.ensureReady({ model });
  } catch (e) {
    const err = new Error(
      e instanceof Error ? e.message : "Runtime IA indisponible"
    );
    (err as Error & { code?: string }).code = "MODEL_UNAVAILABLE";
    throw err;
  }

  const compactItems = params.items.slice(0, 800).map((it) => ({
    name: it.name,
    relativePath: it.relativePath,
    isDirectory: Boolean(it.isDirectory),
    extension: it.extension ?? "",
    sizeBytes: it.sizeBytes ?? 0,
    parentRelativePath: it.parentRelativePath ?? "",
    depth: it.depth ?? 0,
    fileId: it.fileId,
  }));

  const userPayload = {
    rootId: params.rootId,
    rootRelativePath: params.rootRelativePath || "",
    protectedPaths: params.protectedPaths ?? [],
    instruction: params.instruction?.trim() || null,
    items: compactItems,
  };

  let raw: string;
  try {
    const response = await runtime.chat({
      requestId: nanoid(),
      model,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        {
          role: "user",
          content: `Inventaire et contraintes (JSON):\n${JSON.stringify(userPayload)}`,
        },
      ],
      temperature: 0.1,
      maxTokens: 2500,
      signal: AbortSignal.timeout(45_000),
      reasoningEffort: "none",
    });
    raw = responseText(response);
  } catch (e) {
    const err = new Error(
      e instanceof Error ? e.message : "Échec appel modèle"
    );
    (err as Error & { code?: string }).code = "MODEL_UNAVAILABLE";
    throw err;
  }

  if (!raw) {
    const err = new Error("Réponse modèle vide");
    (err as Error & { code?: string }).code = "INVALID_AI_RESPONSE";
    throw err;
  }

  let parsed: unknown;
  try {
    parsed = extractJsonObject(raw);
  } catch (e) {
    const err = new Error(
      e instanceof Error ? e.message : "JSON invalide"
    );
    (err as Error & { code?: string }).code = "INVALID_AI_RESPONSE";
    throw err;
  }

  if (!parsed || typeof parsed !== "object") {
    const err = new Error("Structure JSON invalide");
    (err as Error & { code?: string }).code = "INVALID_AI_RESPONSE";
    throw err;
  }

  const obj = parsed as Record<string, unknown>;
  const summary =
    typeof obj.summary === "string" ? obj.summary.trim() : "Proposition IA";
  const proposedDirectories = Array.isArray(obj.proposedDirectories)
    ? obj.proposedDirectories.filter((d): d is string => typeof d === "string")
    : [];
  const warnings = Array.isArray(obj.warnings)
    ? obj.warnings.filter((w): w is string => typeof w === "string")
    : [];
  const rawMoves = Array.isArray(obj.moves) ? obj.moves : [];
  const moves: OrganizePlanMove[] = [];
  for (const m of rawMoves) {
    if (!m || typeof m !== "object") continue;
    const row = m as Record<string, unknown>;
    const source =
      typeof row.source === "string"
        ? row.source
        : typeof row.sourceRelativePath === "string"
          ? row.sourceRelativePath
          : null;
    const destination =
      typeof row.destination === "string"
        ? row.destination
        : typeof row.destinationRelativePath === "string"
          ? row.destinationRelativePath
          : null;
    if (!source || !destination) continue;
    moves.push({
      source,
      destination,
      confidence: clampConfidence(row.confidence),
      reason:
        typeof row.reason === "string" && row.reason.trim()
          ? row.reason.trim()
          : "Proposition IA",
    });
  }

  if (moves.length === 0) {
    const err = new Error("Aucun déplacement dans la réponse IA");
    (err as Error & { code?: string }).code = "INVALID_AI_RESPONSE";
    throw err;
  }

  return {
    summary: summary || `Proposition IA (${moves.length} déplacements)`,
    proposedDirectories,
    moves,
    warnings:
      warnings.length > 0
        ? warnings
        : ["Aucune suppression : déplacements uniquement."],
  };
}
