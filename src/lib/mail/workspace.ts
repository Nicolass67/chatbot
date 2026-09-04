import { eq } from "drizzle-orm";
import { getDb } from "@/lib/db";
import { conversations } from "@/lib/db/schema";

const MAIL_WORKSPACE_ID = "mail-workspace";

/** Conversation système pour les actions mail (corbeille, etc.). */
export async function getOrCreateMailWorkspaceConversation(): Promise<string> {
  const db = getDb();
  const existing = await db.query.conversations.findFirst({
    where: eq(conversations.id, MAIL_WORKSPACE_ID),
  });
  if (existing) return MAIL_WORKSPACE_ID;

  await db.insert(conversations).values({
    id: MAIL_WORKSPACE_ID,
    title: "Mail",
    titleSource: "auto",
    chatMode: "chat",
    agentDepth: "standard",
  });

  return MAIL_WORKSPACE_ID;
}
