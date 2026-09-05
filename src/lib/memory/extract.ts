import { nanoid } from "nanoid";
import { getDb } from "@/lib/db";
import { memories } from "@/lib/db/schema";
import { getLocalAIRuntime } from "@/lib/runtime/factory";
import {
  getSettings,
  memoryExtractionSchema,
  memoryCategorySchema,
  type AppSettings,
} from "@/lib/settings/service";
import type { SavedMemoryItem } from "./saved-memory";
import { memoryRetriever } from "./search";

const MIN_IMPORTANCE = 0.5;

export async function insertMemoryIfValid(input: {
  content: string;
  category: string;
  importance: number;
}): Promise<SavedMemoryItem | null> {
  const parsed = memoryCategorySchema.safeParse(input.category);
  if (!parsed.success || input.importance < MIN_IMPORTANCE) return null;
  if (input.content.length < 10) return null;

  const existing = await memoryRetriever.search(input.content.slice(0, 100), 3);
  const duplicate = existing.some(
    (m) =>
      m.content.toLowerCase().includes(input.content.toLowerCase().slice(0, 30)) ||
      input.content.toLowerCase().includes(m.content.toLowerCase().slice(0, 30))
  );
  if (duplicate) return null;

  const db = getDb();
  const id = nanoid();
  const now = new Date().toISOString();
  await db.insert(memories).values({
    id,
    content: input.content,
    category: parsed.data,
    importance: input.importance,
    createdAt: now,
    updatedAt: now,
  });

  return {
    id,
    content: input.content,
    category: parsed.data,
  };
}

export async function memorizeFromText(
  content: string,
  settings?: AppSettings
): Promise<{ success: boolean; reason?: string }> {
  const s = settings ?? (await getSettings());
  if (!s.memoryEnabled) {
    return { success: false, reason: "Mémoire désactivée" };
  }

  const inserted = await insertMemoryIfValid({
    content,
    category: "other",
    importance: 0.8,
  });

  return inserted
    ? { success: true }
    : { success: false, reason: "Contenu invalide ou déjà mémorisé" };
}

export async function extractMemoriesAsync(
  userMessage: string,
  assistantMessage: string
): Promise<SavedMemoryItem[]> {
  const settings = await getSettings();
  if (!settings.memoryEnabled || !settings.selectedModel) return [];

  const runtime = getLocalAIRuntime();
  const prompt = `Analyse cette conversation et décide toi-même si des informations PERSONNELLES durables sur l'utilisateur méritent d'être mémorisées long terme.

Mémorise notamment (si présents): âge, prénom, localisation, métier, préférences, matériel, projets, habitudes.
Formule chaque fait à la 3e personne, ≥10 caractères (ex: "L'utilisateur a 26 ans").
Importance ≥ 0.7 pour l'identité. Catégorie identity → "other".

NE mémorise PAS: questions ponctuelles, infos temporaires, secrets (mots de passe, tokens, carte), bavardage sans intérêt futur.

Réponds UNIQUEMENT en JSON valide:
{"shouldRemember":boolean,"memories":[{"content":"...","category":"preference|hardware|project|habit|communication|other","importance":0.0-1.0}]}

Utilisateur: ${userMessage}
Assistant: ${assistantMessage}`;

  try {
    const response = await runtime.chat({
      requestId: nanoid(),
      model: settings.selectedModel,
      messages: [{ role: "user", content: prompt }],
      temperature: 0.1,
      maxTokens: 512,
    });

    const jsonMatch = response.content.match(/\{[\s\S]*\}/);
    if (!jsonMatch) return [];

    const parsed = memoryExtractionSchema.safeParse(JSON.parse(jsonMatch[0]));
    if (!parsed.success || !parsed.data.shouldRemember) return [];

    const saved: SavedMemoryItem[] = [];
    for (const mem of parsed.data.memories) {
      const inserted = await insertMemoryIfValid(mem);
      if (inserted) saved.push(inserted);
    }
    return saved;
  } catch {
    return [];
  }
}

export async function deleteAllMemories(): Promise<void> {
  const db = getDb();
  await db.delete(memories);
}

export async function findMemoriesSearch(query: string) {
  return memoryRetriever.search(query, 20);
}

export async function exportMemoriesJson() {
  const db = getDb();
  return db.query.memories.findMany();
}

export async function importMemoriesJson(
  items: Array<{ content: string; category: string; importance: number }>,
  mode: "merge" | "replace"
) {
  if (mode === "replace") {
    await deleteAllMemories();
  }
  for (const item of items) {
    await insertMemoryIfValid(item);
  }
}
