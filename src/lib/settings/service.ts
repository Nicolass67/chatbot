import { z } from "zod";
import { eq } from "drizzle-orm";
import { getEnv } from "@/lib/config/env";
import { getDb } from "@/lib/db";
import { appSettings } from "@/lib/db/schema";
import { normalizeAppDefaultReasoningMode } from "@/lib/runtime/reasoning-types";

export const memoryCategorySchema = z.enum([
  "preference",
  "hardware",
  "project",
  "habit",
  "communication",
  "other",
]);

export const appSettingsSchema = z.object({
  selectedModel: z.string().default(""),
  temperature: z.number().min(0).max(2).default(0.7),
  maxTokens: z.number().int().min(1).max(128000).default(4096),
  contextLength: z.number().int().min(512).max(200000).default(8192),
  systemPrompt: z
    .string()
    .default(
      "Tu es un assistant IA utile, précis et concis. Réponds en français sauf demande contraire. N'utilise jamais de tableaux markdown : préfère des listes à puces et des sous-titres pour structurer les informations."
    ),
  memoryEnabled: z.boolean().default(true),
  webSearchEnabled: z.boolean().default(true),
  webSearchMaxResults: z.number().int().min(1).max(20).default(5),
  webSearchTimeoutMs: z.number().int().min(1000).default(25000),
  idleTimeoutMinutes: z.number().int().min(1).max(120).default(10),
  recentMessagesCount: z.number().int().min(2).max(50).default(10),
  maxAttachmentSizeMb: z.number().min(1).max(100).default(20),
  maxAttachmentsPerMessage: z.number().int().min(1).max(20).default(10),
  defaultReasoningEffort: z.string().nullable().default("off"),
  agentMaxStepsFast: z.number().int().min(1).max(50).default(5),
  agentMaxStepsStandard: z.number().int().min(1).max(50).default(12),
  agentMaxStepsThorough: z.number().int().min(1).max(50).default(25),
  agentMaxToolCalls: z.number().int().min(1).max(100).default(40),
  agentMaxExecutionTimeMs: z.number().int().min(10000).default(300000),
});

export type AppSettings = z.infer<typeof appSettingsSchema>;

const SETTINGS_KEY = "app";
const MIN_WEB_SEARCH_TIMEOUT_MS = 25000;

function envDefaults(): AppSettings {
  const env = getEnv();
  return appSettingsSchema.parse({
    webSearchEnabled: env.WEB_SEARCH_ENABLED,
    webSearchMaxResults: env.WEB_SEARCH_MAX_RESULTS,
    webSearchTimeoutMs: env.WEB_SEARCH_TIMEOUT_MS,
  });
}

export async function getSettings(): Promise<AppSettings> {
  const db = getDb();
  const row = await db.query.appSettings.findFirst({
    where: eq(appSettings.key, SETTINGS_KEY),
  });

  if (!row) {
    const defaults = envDefaults();
    await db.insert(appSettings).values({
      key: SETTINGS_KEY,
      value: JSON.stringify(defaults),
    });
    return defaults;
  }

  const parsed = appSettingsSchema.parse(JSON.parse(row.value));
  let migrated = parsed;
  let needsSave = false;

  if (parsed.defaultReasoningEffort === "on") {
    migrated = { ...migrated, defaultReasoningEffort: "off" };
    needsSave = true;
  }

  const normalizedDefault = normalizeAppDefaultReasoningMode(
    parsed.defaultReasoningEffort
  );
  if (normalizedDefault !== parsed.defaultReasoningEffort) {
    migrated = { ...migrated, defaultReasoningEffort: normalizedDefault };
    needsSave = true;
  }

  const env = getEnv();
  const minTimeout = Math.max(MIN_WEB_SEARCH_TIMEOUT_MS, env.WEB_SEARCH_TIMEOUT_MS);
  if (migrated.webSearchTimeoutMs < minTimeout) {
    migrated = { ...migrated, webSearchTimeoutMs: minTimeout };
    needsSave = true;
  }

  if (!needsSave) {
    return migrated;
  }

  await db
    .insert(appSettings)
    .values({ key: SETTINGS_KEY, value: JSON.stringify(migrated) })
    .onConflictDoUpdate({
      target: appSettings.key,
      set: { value: JSON.stringify(migrated) },
    });
  return migrated;
}

export async function updateSettings(
  partial: Partial<AppSettings>
): Promise<AppSettings> {
  const current = await getSettings();
  const merged = appSettingsSchema.parse({
    ...current,
    ...partial,
    ...(partial.defaultReasoningEffort !== undefined
      ? {
          defaultReasoningEffort: normalizeAppDefaultReasoningMode(
            partial.defaultReasoningEffort
          ),
        }
      : {}),
  });
  const db = getDb();

  await db
    .insert(appSettings)
    .values({ key: SETTINGS_KEY, value: JSON.stringify(merged) })
    .onConflictDoUpdate({
      target: appSettings.key,
      set: { value: JSON.stringify(merged) },
    });

  return merged;
}

export const memoryExtractionSchema = z.object({
  shouldRemember: z.boolean(),
  memories: z.array(
    z.object({
      content: z.string().min(10),
      category: memoryCategorySchema,
      importance: z.number().min(0).max(1),
    })
  ),
});

export type MemoryExtractionResult = z.infer<typeof memoryExtractionSchema>;
