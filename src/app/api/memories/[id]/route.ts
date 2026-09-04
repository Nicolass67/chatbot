export const runtime = "nodejs";

import { eq } from "drizzle-orm";
import { z } from "zod";
import { getDb } from "@/lib/db";
import { memories } from "@/lib/db/schema";

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const db = getDb();
  await db.delete(memories).where(eq(memories.id, id));
  return Response.json({ ok: true });
}

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const body = z
    .object({
      content: z.string().min(1).max(4000),
    })
    .parse(await request.json());

  const db = getDb();
  const now = new Date().toISOString();
  await db
    .update(memories)
    .set({ content: body.content, updatedAt: now })
    .where(eq(memories.id, id));

  const updated = await db.query.memories.findFirst({
    where: (m, { eq }) => eq(m.id, id),
  });
  if (!updated) {
    return Response.json({ error: "not_found" }, { status: 404 });
  }
  return Response.json(updated);
}
