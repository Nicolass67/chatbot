export const runtime = "nodejs";

import { z } from "zod";
import { importMemoriesJson } from "@/lib/memory/extract";
import { memoryCategorySchema } from "@/lib/settings/service";

const importSchema = z.object({
  mode: z.enum(["merge", "replace"]).default("merge"),
  memories: z.array(
    z.object({
      content: z.string().min(10),
      category: memoryCategorySchema,
      importance: z.number().min(0).max(1),
    })
  ),
});

export async function POST(request: Request) {
  const body = importSchema.parse(await request.json());
  await importMemoriesJson(body.memories, body.mode);
  return Response.json({ ok: true, count: body.memories.length });
}
