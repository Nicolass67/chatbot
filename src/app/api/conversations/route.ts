export const runtime = "nodejs";

import { nanoid } from "nanoid";
import { z } from "zod";
import { getDb } from "@/lib/db";
import { conversations } from "@/lib/db/schema";
import { listConversations } from "@/lib/export/conversation";
import {
  getReasoningCapabilities,
  resolveReasoningMode,
} from "@/lib/runtime/reasoning";
import { getSettings } from "@/lib/settings/service";

const scopeSchema = z.enum(["general", "mail", "files"]);

const createSchema = z
  .object({
    scope: scopeSchema.optional().default("general"),
    contextKey: z.string().min(1).max(500).optional(),
    contextLabel: z.string().max(200).optional(),
    title: z.string().min(1).max(200).optional(),
  })
  .strict();

export async function GET(request: Request) {
  const url = new URL(request.url);
  const raw = url.searchParams.get("scope");
  const parsed = scopeSchema.safeParse(raw ?? "general");
  const scope = parsed.success ? parsed.data : "general";
  const items = await listConversations({ scope });
  return Response.json(items);
}

export async function POST(request: Request) {
  const db = getDb();
  const settings = await getSettings();
  const id = nanoid();
  const now = new Date().toISOString();

  let body: z.infer<typeof createSchema> = { scope: "general" };
  const contentType = request.headers.get("content-type") ?? "";
  if (contentType.includes("application/json")) {
    const raw = await request.json().catch(() => ({}));
    body = createSchema.parse(raw ?? {});
  }

  let reasoningEffort = settings.defaultReasoningEffort;
  if (settings.selectedModel && reasoningEffort) {
    const caps = await getReasoningCapabilities(settings.selectedModel);
    reasoningEffort = resolveReasoningMode(reasoningEffort, caps);
  }

  const title =
    body.title?.trim() ||
    (body.scope === "mail"
      ? "Mail Assistant"
      : body.scope === "files"
        ? "Files Assistant"
        : "Nouvelle conversation");

  await db.insert(conversations).values({
    id,
    title,
    titleSource: body.title ? "user" : "auto",
    reasoningEffort,
    scope: body.scope,
    contextKey: body.contextKey ?? null,
    contextLabel: body.contextLabel ?? null,
    createdAt: now,
    updatedAt: now,
  });

  const conv = await db.query.conversations.findFirst({
    where: (c, { eq }) => eq(c.id, id),
  });

  return Response.json(conv, { status: 201 });
}
