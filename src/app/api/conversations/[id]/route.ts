export const runtime = "nodejs";

import { eq } from "drizzle-orm";
import { z } from "zod";
import { getDb } from "@/lib/db";
import { conversations } from "@/lib/db/schema";
import { apiErrorResponse } from "@/lib/http/api-error";

const patchSchema = z.object({
  title: z.string().min(1).max(200).optional(),
  reasoningEffort: z.string().nullable().optional(),
  chatMode: z.enum(["chat", "agent"]).optional(),
  agentDepth: z.enum(["fast", "standard", "thorough"]).optional(),
});

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const db = getDb();
  const conv = await db.query.conversations.findFirst({
    where: eq(conversations.id, id),
  });
  if (!conv) return apiErrorResponse("NOT_FOUND", "Not found");
  return Response.json(conv);
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const body = patchSchema.parse(await request.json());
  const db = getDb();

  const updates: {
    title?: string;
    titleSource?: "auto" | "user";
    reasoningEffort?: string | null;
    chatMode?: "chat" | "agent";
    agentDepth?: "fast" | "standard" | "thorough";
    updatedAt: string;
  } = {
    updatedAt: new Date().toISOString(),
  };
  if (body.title !== undefined) {
    updates.title = body.title;
    updates.titleSource = "user";
  }
  if (body.reasoningEffort !== undefined) updates.reasoningEffort = body.reasoningEffort;
  if (body.chatMode !== undefined) updates.chatMode = body.chatMode;
  if (body.agentDepth !== undefined) updates.agentDepth = body.agentDepth;

  await db.update(conversations).set(updates).where(eq(conversations.id, id));

  const conv = await db.query.conversations.findFirst({
    where: eq(conversations.id, id),
  });
  return Response.json(conv);
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const db = getDb();
  await db.delete(conversations).where(eq(conversations.id, id));
  return Response.json({ ok: true });
}
