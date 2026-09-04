import { nanoid } from "nanoid";
import { eq } from "drizzle-orm";
import { getDb } from "@/lib/db";
import { conversationSummaries, messages } from "@/lib/db/schema";
import { getLocalAIRuntime } from "@/lib/runtime/factory";
import { getSettings } from "@/lib/settings/service";
import { tokenEstimator } from "./token-estimator";
import { maybeGenerateConversationTitle } from "@/lib/conversation/title-generator";

export async function maybeSummarizeConversation(
  conversationId: string
): Promise<void> {
  const settings = await getSettings();
  const db = getDb();

  const allMessages = await db.query.messages.findMany({
    where: eq(messages.conversationId, conversationId),
    orderBy: (m, { asc }) => [asc(m.createdAt)],
  });

  const totalTokens = tokenEstimator.estimateMessages(
    allMessages.map((m) => ({ role: m.role as "user" | "assistant", content: m.content }))
  );

  if (
    allMessages.length <= settings.recentMessagesCount + 5 ||
    totalTokens < settings.contextLength * 0.7
  ) {
    return;
  }

  const cutoff = allMessages.length - settings.recentMessagesCount;
  const toSummarize = allMessages.slice(0, cutoff);
  if (toSummarize.length === 0) return;

  const transcript = toSummarize
    .map((m) => `${m.role}: ${m.content}`)
    .join("\n");

  const runtime = getLocalAIRuntime();
  const model = settings.selectedModel;
  if (!model) return;

  try {
    const response = await runtime.chat({
      requestId: nanoid(),
      model,
      messages: [
        {
          role: "system",
          content:
            "Résume la conversation suivante en préservant les faits, décisions et préférences importantes. Sois concis.",
        },
        { role: "user", content: transcript },
      ],
      temperature: 0.3,
      maxTokens: 1024,
    });

    const coversUntil = toSummarize[toSummarize.length - 1]?.id;
    if (!coversUntil || !response.content) return;

    const existing = await db.query.conversationSummaries.findFirst({
      where: eq(conversationSummaries.conversationId, conversationId),
    });

    const summaryData = {
      content: response.content,
      coversUntilMessageId: coversUntil,
      tokenEstimate: tokenEstimator.estimate(response.content),
      updatedAt: new Date().toISOString(),
    };

    if (existing) {
      await db
        .update(conversationSummaries)
        .set(summaryData)
        .where(eq(conversationSummaries.id, existing.id));
    } else {
      await db.insert(conversationSummaries).values({
        id: nanoid(),
        conversationId,
        ...summaryData,
      });
    }

    void maybeGenerateConversationTitle({ conversationId });
  } catch {
    // summarization is best-effort
  }
}
