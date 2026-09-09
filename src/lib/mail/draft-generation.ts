import { nanoid } from "nanoid";
import { getSettings } from "@/lib/settings/service";
import { getLocalAIRuntime } from "@/lib/runtime/factory";
import {
  persistEmailDraft,
  updateEmailDraft,
} from "@/lib/email/draft";
import { getOrCreateMailWorkspaceConversation } from "@/lib/mail/workspace";
import {
  MAIL_COMPOSE_DRAFT_SYSTEM,
  MAIL_DRAFT_REWRITE_SYSTEM,
  buildComposeUserPrompt,
  buildRewriteUserPrompt,
  stripRewriteMeta,
} from "@/lib/mail/draft-rewrite";

function resolveModel(
  settings: Awaited<ReturnType<typeof getSettings>>,
  model?: string
): string {
  const resolved = model?.trim() || settings.selectedModel;
  if (!resolved) throw new Error("Aucun modèle sélectionné.");
  return resolved;
}

async function completeText(input: {
  system: string;
  user: string;
  model?: string;
}): Promise<string> {
  const settings = await getSettings();
  const runtime = getLocalAIRuntime();
  const resolvedModel = resolveModel(settings, input.model);
  let full = "";
  await runtime.stream(
    {
      requestId: nanoid(),
      model: resolvedModel,
      messages: [
        { role: "system", content: input.system },
        { role: "user", content: input.user },
      ],
      temperature: 0.4,
      maxTokens: 2048,
      stream: true,
    },
    {
      onToken: (token) => {
        full += token;
      },
      onDone: () => {},
      onError: (err) => {
        throw err;
      },
    }
  );
  const cleaned = stripRewriteMeta(full);
  if (cleaned.trim().length < 8) {
    throw new Error("Réécriture vide.");
  }
  return cleaned;
}

export async function rewriteMailDraftBody(input: {
  instruction: string;
  body: string;
  to?: string;
  subject?: string;
  draftId?: string;
  userId: string;
  model?: string;
}): Promise<{ bodyText: string; draftId?: string }> {
  const instruction = input.instruction.trim();
  const body = input.body.trim();
  if (!instruction) throw new Error("Instruction vide.");
  if (body.length < 1) throw new Error("Brouillon vide.");

  const bodyText = await completeText({
    system: MAIL_DRAFT_REWRITE_SYSTEM,
    user: buildRewriteUserPrompt({
      instruction,
      body: body.slice(0, 8000),
      to: input.to,
      subject: input.subject,
    }),
    model: input.model,
  });

  const draftId = input.draftId?.trim();
  if (draftId && !draftId.startsWith("local-")) {
    try {
      await updateEmailDraft(draftId, input.userId, { bodyText });
    } catch {
      // Le corps réécrit reste renvoyé même si le PATCH échoue.
    }
  }
  return { bodyText, draftId: draftId || undefined };
}

export async function composeMailDraftBody(input: {
  instruction: string;
  recipientHint?: string;
  subject?: string;
  conversationId?: string;
  userId: string;
  model?: string;
}): Promise<{
  draftId: string;
  bodyText: string;
  subject: string;
  to: string[];
}> {
  const instruction = input.instruction.trim();
  if (!instruction) throw new Error("Instruction vide.");

  const bodyText = await completeText({
    system: MAIL_COMPOSE_DRAFT_SYSTEM,
    user: buildComposeUserPrompt({
      instruction,
      recipientHint: input.recipientHint,
    }),
    model: input.model,
  });

  const hint = (input.recipientHint ?? "").trim();
  const to = hint.includes("@") ? [hint] : [];
  const subject = (input.subject ?? "").trim();
  const conversationId =
    input.conversationId?.trim() || (await getOrCreateMailWorkspaceConversation());

  const draft = await persistEmailDraft({
    userId: input.userId,
    conversationId,
    provider: "gmail",
    to,
    subject,
    bodyText,
  });

  return {
    draftId: draft.id,
    bodyText: draft.bodyText,
    subject: draft.subject,
    to,
  };
}
