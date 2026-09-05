import { nanoid } from "nanoid";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { contentToPlainText } from "@/lib/runtime/capabilities";
import { getDb } from "@/lib/db";
import { conversationSummaries, conversations, messages } from "@/lib/db/schema";
import { getLocalAIRuntime } from "@/lib/runtime/factory";
import { getSettings } from "@/lib/settings/service";

export const TITLE_MAX_LENGTH = 80;
/** @deprecated Conservé pour compat tests — le titre auto ne se rafraîchit plus périodiquement. */
export const TITLE_REFRESH_EVERY_MESSAGES = 6;
const TITLE_LLM_MAX_TOKENS = 80;
const TITLE_TIMEOUT_MS = 8_000;

const titleSchema = z.object({
  title: z.string().min(1).max(TITLE_MAX_LENGTH),
});

const GENERIC_USER_OPENERS =
  /^(bonjour|salut|coucou|hello|hi|hey|bonsoir|merci|ok|okay|oui|non|svp|s'il te plait|please|question|j['']ai une question)[\s!.?]*$/i;

/** Titres placeholder — encore éligibles à la génération auto (une seule fois). */
export const PLACEHOLDER_TITLES = new Set([
  "Nouvelle conversation",
  "Nouveau chat",
  "Mail Assistant",
  "Files Assistant",
  "Assistant Mail",
  "Assistant Files",
]);

export function isPlaceholderTitle(title: string): boolean {
  return PLACEHOLDER_TITLES.has(title.trim());
}

export function normalizeConversationTitle(raw: string): string {
  const cleaned = raw
    .replace(/^["'«»]+|["'«»]+$/g, "")
    .replace(/\s+/g, " ")
    .trim();
  if (!cleaned) return "Conversation";
  return cleaned.length > TITLE_MAX_LENGTH
    ? `${cleaned.slice(0, TITLE_MAX_LENGTH - 1)}…`
    : cleaned;
}

function extractJsonFromContent(content: string): unknown {
  const trimmed = content.trim();
  const fenceMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
  const jsonStr = fenceMatch ? fenceMatch[1].trim() : trimmed;
  const start = jsonStr.indexOf("{");
  const end = jsonStr.lastIndexOf("}");
  if (start === -1 || end === -1) {
    throw new Error("Réponse titre sans JSON valide");
  }
  return JSON.parse(jsonStr.slice(start, end + 1));
}

export function parseTitleResponse(content: string): string {
  const raw = extractJsonFromContent(content);
  return normalizeConversationTitle(titleSchema.parse(raw).title);
}

export function fallbackTitleFromExchange(params: {
  userText: string;
  assistantText: string;
}): string {
  const user = params.userText.trim();
  const assistant = params.assistantText.trim();

  if (user && !GENERIC_USER_OPENERS.test(user) && user.length <= 70) {
    return normalizeConversationTitle(user);
  }

  const assistantLine =
    assistant
      .split(/\n+/)
      .map((line) => line.trim())
      .find((line) => line.length >= 12) ?? assistant;

  const words = assistantLine.split(/\s+/).slice(0, 10).join(" ");
  return normalizeConversationTitle(words || user || "Conversation");
}

/** Une seule génération auto : placeholder + ≥2 messages + pas de titre manuel. */
export function shouldAutoUpdateTitle(params: {
  title: string;
  titleSource: string | null | undefined;
  messageCount: number;
}): boolean {
  if (params.titleSource === "user") return false;
  if (params.messageCount < 2) return false;
  return isPlaceholderTitle(params.title);
}

function buildTitlePromptContext(
  transcript: string,
  summary?: string | null
): string {
  if (summary?.trim()) {
    return `Résumé existant:\n${summary.trim()}\n\nÉchange récent:\n${transcript}`;
  }
  return transcript;
}

async function buildTranscript(conversationId: string): Promise<{
  transcript: string;
  userText: string;
  assistantText: string;
  summary: string | null;
}> {
  const db = getDb();
  const [allMessages, summaryRow] = await Promise.all([
    db.query.messages.findMany({
      where: eq(messages.conversationId, conversationId),
      orderBy: (m, { asc }) => [asc(m.createdAt)],
    }),
    db.query.conversationSummaries.findFirst({
      where: eq(conversationSummaries.conversationId, conversationId),
    }),
  ]);

  const recent = allMessages.slice(-6);
  const transcript = recent
    .map((m) => {
      const text = contentToPlainText(m.content).trim();
      return text ? `${m.role}: ${text}` : null;
    })
    .filter(Boolean)
    .join("\n");

  const firstUser = allMessages.find((m) => m.role === "user");
  const firstAssistant = allMessages.find((m) => m.role === "assistant");

  return {
    transcript,
    userText: contentToPlainText(firstUser?.content ?? ""),
    assistantText: contentToPlainText(firstAssistant?.content ?? ""),
    summary: summaryRow?.content ?? null,
  };
}

async function generateTitleWithLlm(promptContext: string): Promise<string | null> {
  const settings = await getSettings();
  const model = settings.selectedModel;
  if (!model) return null;

  const runtime = getLocalAIRuntime();

  try {
    const response = await runtime.chat({
      requestId: nanoid(),
      model,
      messages: [
        {
          role: "system",
          content: `Tu génères un titre de conversation pour une sidebar.
Règles:
- 4 à 10 mots maximum
- résume le SUJET de la conversation, pas la formulation du premier message
- pas de guillemets
- en français
- réponds UNIQUEMENT avec un JSON: {"title":"..."}`,
        },
        {
          role: "user",
          content: promptContext,
        },
      ],
      temperature: 0,
      maxTokens: TITLE_LLM_MAX_TOKENS,
      signal: AbortSignal.timeout(TITLE_TIMEOUT_MS),
      reasoningEffort: "none",
    });

    if (!response.content?.trim()) return null;
    return parseTitleResponse(response.content);
  } catch {
    return null;
  }
}

export async function maybeGenerateConversationTitle(params: {
  conversationId: string;
  onTitle?: (title: string) => void;
}): Promise<string | null> {
  const db = getDb();
  const conv = await db.query.conversations.findFirst({
    where: eq(conversations.id, params.conversationId),
  });
  if (!conv) return null;

  const messageCount = await db.query.messages.findMany({
    where: eq(messages.conversationId, params.conversationId),
    columns: { id: true },
  }).then((rows) => rows.length);

  if (
    !shouldAutoUpdateTitle({
      title: conv.title,
      titleSource: conv.titleSource,
      messageCount,
    })
  ) {
    return null;
  }

  const { transcript, userText, assistantText, summary } =
    await buildTranscript(params.conversationId);

  if (!transcript.trim()) return null;

  const promptContext = buildTitlePromptContext(transcript, summary);
  const generated =
    (await generateTitleWithLlm(promptContext)) ??
    fallbackTitleFromExchange({ userText, assistantText });

  await db
    .update(conversations)
    .set({
      title: generated,
      titleSource: "auto",
      updatedAt: new Date().toISOString(),
    })
    .where(eq(conversations.id, params.conversationId));

  params.onTitle?.(generated);
  return generated;
}
