export const runtime = "nodejs";

import { z } from "zod";
import { getDb } from "@/lib/db";
import {
  deleteAllMemories,
  findMemoriesSearch,
  memorizeFromText,
} from "@/lib/memory/extract";

export async function GET(request: Request) {
  const q = new URL(request.url).searchParams.get("q");
  if (q) {
    const results = await findMemoriesSearch(q);
    return Response.json(results);
  }
  const db = getDb();
  const items = await db.query.memories.findMany({
    orderBy: (m, { desc }) => [desc(m.updatedAt)],
  });
  return Response.json(items);
}

export async function DELETE() {
  await deleteAllMemories();
  return Response.json({ ok: true });
}

export async function POST(request: Request) {
  const body = z
    .object({
      content: z.string().min(1).optional(),
      messageId: z.string().optional(),
    })
    .parse(await request.json());

  let content = body.content ?? "";
  if (body.messageId) {
    const db = getDb();
    const msg = await db.query.messages.findFirst({
      where: (m, { eq }) => eq(m.id, body.messageId!),
    });
    if (msg) content = msg.content;
  }

  if (!content) {
    return Response.json({ success: false, reason: "Contenu vide" }, { status: 400 });
  }

  const result = await memorizeFromText(content);
  return Response.json(result, { status: result.success ? 201 : 400 });
}
