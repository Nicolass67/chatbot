import { desc, eq, isNull, or } from "drizzle-orm";
import { getDb } from "@/lib/db";
import { conversations, messages, toolCalls } from "@/lib/db/schema";

export async function exportConversationMarkdown(conversationId: string) {
  const db = getDb();
  const conv = await db.query.conversations.findFirst({
    where: eq(conversations.id, conversationId),
  });
  if (!conv) throw new Error("Conversation introuvable");

  const msgs = await db.query.messages.findMany({
    where: eq(messages.conversationId, conversationId),
    orderBy: (m, { asc }) => [asc(m.createdAt)],
    with: { sources: true },
  });

  let md = `# ${conv.title}\n\n`;
  md += `_Créée le ${conv.createdAt}_\n\n`;

  for (const msg of msgs) {
    const role = msg.role === "user" ? "Utilisateur" : "Assistant";
    md += `## ${role}\n\n${msg.content}\n\n`;
    if (msg.sources?.length) {
      md += "### Sources\n\n";
      for (const s of msg.sources) {
        md += `- [${s.title}](${s.url}) — ${s.domain}\n`;
        if (s.snippet) md += `  > ${s.snippet}\n`;
      }
      md += "\n";
    }
  }

  return md;
}

export async function exportConversationJson(conversationId: string) {
  const db = getDb();
  const conv = await db.query.conversations.findFirst({
    where: eq(conversations.id, conversationId),
  });
  if (!conv) throw new Error("Conversation introuvable");

  const msgs = await db.query.messages.findMany({
    where: eq(messages.conversationId, conversationId),
    orderBy: (m, { asc }) => [asc(m.createdAt)],
    with: { sources: true, attachments: true },
  });

  const calls = await db.query.toolCalls.findMany({
    where: eq(toolCalls.conversationId, conversationId),
    orderBy: (t, { asc }) => [asc(t.createdAt)],
  });

  return { conversation: conv, messages: msgs, toolCalls: calls };
}

export async function listConversations(opts?: {
  scope?: "general" | "mail" | "files";
}) {
  const scope = opts?.scope ?? "general";
  const db = getDb();
  const all = await db.query.conversations.findMany({
    where:
      scope === "general"
        ? or(eq(conversations.scope, "general"), isNull(conversations.scope))
        : eq(conversations.scope, scope),
    orderBy: [desc(conversations.updatedAt)],
    with: {
      messages: {
        columns: { id: true },
        limit: 1,
      },
    },
  });

  return all
    .filter((c) => scope !== "general" || c.messages.length > 0)
    .map(
      ({
        id,
        title,
        createdAt,
        updatedAt,
        scope: convScope,
        contextKey,
        contextLabel,
        chatMode,
        reasoningEffort,
      }) => ({
        id,
        title,
        createdAt,
        updatedAt,
        scope: convScope ?? "general",
        contextKey: contextKey ?? null,
        contextLabel: contextLabel ?? null,
        chatMode: chatMode ?? "chat",
        reasoningEffort: reasoningEffort ?? null,
      })
    );
}
