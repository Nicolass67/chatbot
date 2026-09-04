import fs from "node:fs";
import { nanoid } from "nanoid";
import { and, eq, inArray } from "drizzle-orm";
import { hashDraftPayload } from "@/lib/actions/service";
import { getAttachmentsByIds, markAttachmentsAttached } from "@/lib/attachments/storage";
import { getDb } from "@/lib/db";
import { attachments, emailDrafts, type EmailDraft } from "@/lib/db/schema";
import { getEmailProvider } from "@/lib/integrations/email";
import type {
  EmailDraftAttachmentPreview,
  EmailDraftPreview,
  PersistEmailDraftInput,
  UpdateEmailDraftInput,
} from "./types";
import { EmailDraftError } from "./types";

function parseAddressJson(raw: string): string[] {
  try {
    const parsed = JSON.parse(raw) as unknown;
    return Array.isArray(parsed)
      ? parsed.filter((item): item is string => typeof item === "string")
      : [];
  } catch {
    return [];
  }
}

function serializeAddresses(values?: string[]): string {
  return JSON.stringify(values ?? []);
}

function parseAttachmentIds(raw: string | null | undefined): string[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw) as unknown;
    return Array.isArray(parsed)
      ? parsed.filter((item): item is string => typeof item === "string")
      : [];
  } catch {
    return [];
  }
}

function serializeAttachmentIds(ids?: string[]): string {
  const unique = [...new Set((ids ?? []).filter(Boolean))];
  return JSON.stringify(unique);
}

function rehashDraft(draft: {
  toJson: string;
  ccJson: string;
  bccJson: string;
  subject: string;
  bodyText: string;
  attachmentIdsJson: string;
}): string {
  return hashDraftPayload(draft);
}

async function resolveAttachmentPreviews(
  attachmentIdsJson: string | null | undefined
): Promise<EmailDraftAttachmentPreview[]> {
  const ids = parseAttachmentIds(attachmentIdsJson);
  if (ids.length === 0) return [];
  const rows = await getAttachmentsByIds(ids);
  const byId = new Map(rows.map((row) => [row.id, row]));
  return ids
    .map((id) => byId.get(id))
    .filter((row): row is NonNullable<typeof row> => Boolean(row))
    .map((row) => ({
      id: row.id,
      filename: row.filename,
      mimeType: row.mimeType,
      sizeBytes: row.sizeBytes,
    }));
}

export async function toEmailDraftPreview(
  draft: EmailDraft
): Promise<EmailDraftPreview> {
  return {
    draftId: draft.id,
    conversationId: draft.conversationId,
    to: parseAddressJson(draft.toJson),
    cc: parseAddressJson(draft.ccJson),
    bcc: parseAddressJson(draft.bccJson),
    subject: draft.subject,
    bodyText: draft.bodyText,
    status: draft.status,
    contentHash: draft.contentHash,
    threadId: draft.threadId,
    inReplyToMessageId: draft.inReplyToMessageId,
    providerDraftId: draft.providerDraftId,
    attachments: await resolveAttachmentPreviews(draft.attachmentIdsJson),
    requiresConfirmation: true,
  };
}

export async function getEmailDraftForUser(
  draftId: string,
  userId: string
): Promise<EmailDraft | null> {
  const db = getDb();
  const draft = await db.query.emailDrafts.findFirst({
    where: and(eq(emailDrafts.id, draftId), eq(emailDrafts.userId, userId)),
  });
  return draft ?? null;
}

export async function requireEmailDraftForUser(
  draftId: string,
  userId: string
): Promise<EmailDraft> {
  const draft = await getEmailDraftForUser(draftId, userId);
  if (!draft) {
    throw new EmailDraftError("NOT_FOUND", "Brouillon introuvable.");
  }
  return draft;
}

export async function persistEmailDraft(
  input: PersistEmailDraftInput
): Promise<EmailDraft> {
  const toJson = serializeAddresses(input.to);
  const ccJson = serializeAddresses(input.cc);
  const bccJson = serializeAddresses(input.bcc);
  const attachmentIdsJson = serializeAttachmentIds(input.attachmentIds);
  const contentHash = rehashDraft({
    toJson,
    ccJson,
    bccJson,
    subject: input.subject,
    bodyText: input.bodyText,
    attachmentIdsJson,
  });

  const id = nanoid();
  const now = new Date().toISOString();
  const db = getDb();

  await db.insert(emailDrafts).values({
    id,
    userId: input.userId,
    conversationId: input.conversationId,
    threadId: input.threadId ?? null,
    provider: input.provider,
    providerDraftId: input.providerDraftId ?? null,
    toJson,
    ccJson,
    bccJson,
    subject: input.subject,
    bodyText: input.bodyText,
    attachmentIdsJson,
    contentHash,
    status: "draft",
    inReplyToMessageId: input.inReplyToMessageId ?? null,
    createdAt: now,
    updatedAt: now,
  });

  if (input.attachmentIds && input.attachmentIds.length > 0) {
    await markAttachmentsAttached(input.attachmentIds);
  }

  const created = await getEmailDraftForUser(id, input.userId);
  if (!created) {
    throw new EmailDraftError("PERSIST_FAILED", "Échec de création du brouillon.");
  }
  return created;
}

async function loadOutgoingAttachments(attachmentIdsJson: string) {
  const ids = parseAttachmentIds(attachmentIdsJson);
  if (ids.length === 0) return [];

  const rows = await getAttachmentsByIds(ids);
  const byId = new Map(rows.map((row) => [row.id, row]));
  const missing = ids.filter((id) => !byId.has(id));
  if (missing.length > 0) {
    throw new EmailDraftError(
      "VALIDATION_ERROR",
      "Certaines pièces jointes sont introuvables."
    );
  }

  return ids.map((id) => {
    const row = byId.get(id)!;
    if (!fs.existsSync(row.localPath)) {
      throw new EmailDraftError(
        "VALIDATION_ERROR",
        `Fichier manquant pour « ${row.filename} ».`
      );
    }
    const content = fs.readFileSync(row.localPath);
    return {
      filename: row.filename,
      mimeType: row.mimeType || "application/octet-stream",
      contentBase64: content.toString("base64"),
    };
  });
}

/** Charge les PJ pour un createDraft Gmail (outil create-draft). */
export async function loadOutgoingAttachmentsByIds(attachmentIds: string[]) {
  return loadOutgoingAttachments(serializeAttachmentIds(attachmentIds));
}

async function deleteProviderDraftBestEffort(
  userId: string,
  providerDraftId: string | null | undefined
): Promise<void> {
  if (!providerDraftId) return;
  try {
    const provider = await getEmailProvider(userId);
    await provider.deleteDraft(providerDraftId);
  } catch (error) {
    console.warn(
      "[email/draft] deleteProviderDraft ignored:",
      error instanceof Error ? error.message : error
    );
  }
}

async function syncGmailProviderDraft(
  draft: EmailDraft,
  userId: string
): Promise<string> {
  const provider = await getEmailProvider(userId);
  const to = parseAddressJson(draft.toJson);
  const cc = parseAddressJson(draft.ccJson);
  const bcc = parseAddressJson(draft.bccJson);
  const attachments = await loadOutgoingAttachments(draft.attachmentIdsJson);

  let inReplyToHeader: string | undefined;
  let referencesHeader: string | undefined;
  if (draft.inReplyToMessageId) {
    const replyTarget = await provider.getMessage(draft.inReplyToMessageId);
    inReplyToHeader = replyTarget.id;
    referencesHeader = replyTarget.id;
  }

  const created = await provider.createDraft({
    to,
    cc,
    bcc,
    subject: draft.subject,
    bodyText: draft.bodyText,
    threadId: draft.threadId ?? undefined,
    inReplyToMessageId: draft.inReplyToMessageId ?? undefined,
    inReplyToHeader,
    referencesHeader,
    attachments,
  });

  // Remplace l’ancien brouillon Gmail (sinon il reste « Brouillon » dans le thread).
  if (
    draft.providerDraftId &&
    draft.providerDraftId !== created.providerDraftId
  ) {
    await deleteProviderDraftBestEffort(userId, draft.providerDraftId);
  }

  return created.providerDraftId;
}

export async function updateEmailDraft(
  draftId: string,
  userId: string,
  patch: UpdateEmailDraftInput
): Promise<EmailDraft> {
  const existing = await requireEmailDraftForUser(draftId, userId);

  if (existing.status === "sent") {
    throw new EmailDraftError(
      "INVALID_STATE",
      "Un brouillon déjà envoyé ne peut pas être modifié."
    );
  }

  if (existing.status === "cancelled") {
    throw new EmailDraftError(
      "INVALID_STATE",
      "Ce brouillon est annulé."
    );
  }

  const toJson =
    patch.to !== undefined ? serializeAddresses(patch.to) : existing.toJson;
  const ccJson =
    patch.cc !== undefined ? serializeAddresses(patch.cc) : existing.ccJson;
  const bccJson =
    patch.bcc !== undefined ? serializeAddresses(patch.bcc) : existing.bccJson;
  const subject = patch.subject ?? existing.subject;
  const bodyText = patch.bodyText ?? existing.bodyText;
  const attachmentIdsJson =
    patch.attachmentIds !== undefined
      ? serializeAttachmentIds(patch.attachmentIds)
      : existing.attachmentIdsJson;

  if (patch.attachmentIds !== undefined) {
    const rows = await getAttachmentsByIds(patch.attachmentIds);
    if (rows.length !== patch.attachmentIds.length) {
      throw new EmailDraftError(
        "VALIDATION_ERROR",
        "Certaines pièces jointes sont introuvables."
      );
    }
    await markAttachmentsAttached(patch.attachmentIds);
  }

  if (parseAddressJson(toJson).length === 0) {
    throw new EmailDraftError(
      "VALIDATION_ERROR",
      "Au moins un destinataire est requis."
    );
  }

  const contentHash = rehashDraft({
    toJson,
    ccJson,
    bccJson,
    subject,
    bodyText,
    attachmentIdsJson,
  });

  const now = new Date().toISOString();
  const db = getDb();

  // Invalide le brouillon Gmail figé : il sera recréé au validate (avec PJ à jour).
  if (existing.providerDraftId) {
    await deleteProviderDraftBestEffort(userId, existing.providerDraftId);
  }

  await db
    .update(emailDrafts)
    .set({
      toJson,
      ccJson,
      bccJson,
      subject,
      bodyText,
      attachmentIdsJson,
      contentHash,
      providerDraftId: null,
      status: existing.status === "validated" ? "draft" : existing.status,
      updatedAt: now,
    })
    .where(and(eq(emailDrafts.id, draftId), eq(emailDrafts.userId, userId)));

  return requireEmailDraftForUser(draftId, userId);
}

/** Fusionne des pièces jointes sur un brouillon existant. */
export async function attachFilesToEmailDraft(
  draftId: string,
  userId: string,
  attachmentIds: string[]
): Promise<EmailDraft> {
  const existing = await requireEmailDraftForUser(draftId, userId);
  const current = parseAttachmentIds(existing.attachmentIdsJson);
  const merged = [...new Set([...current, ...attachmentIds])];
  return updateEmailDraft(draftId, userId, { attachmentIds: merged });
}

export async function validateEmailDraft(
  draftId: string,
  userId: string
): Promise<EmailDraft> {
  const existing = await requireEmailDraftForUser(draftId, userId);

  if (existing.status === "sent") {
    throw new EmailDraftError("INVALID_STATE", "Brouillon déjà envoyé.");
  }

  if (existing.status === "cancelled") {
    throw new EmailDraftError("INVALID_STATE", "Brouillon annulé.");
  }

  if (existing.status === "validated") {
    return existing;
  }

  if (!existing.subject.trim() || !existing.bodyText.trim()) {
    throw new EmailDraftError(
      "VALIDATION_ERROR",
      "Objet et corps requis pour valider le brouillon."
    );
  }

  if (parseAddressJson(existing.toJson).length === 0) {
    throw new EmailDraftError(
      "VALIDATION_ERROR",
      "Au moins un destinataire est requis."
    );
  }

  let providerDraftId = existing.providerDraftId;
  if (existing.provider === "gmail") {
    providerDraftId = await syncGmailProviderDraft(existing, userId);
  }

  const now = new Date().toISOString();
  const db = getDb();

  await db
    .update(emailDrafts)
    .set({
      status: "validated",
      providerDraftId,
      updatedAt: now,
    })
    .where(and(eq(emailDrafts.id, draftId), eq(emailDrafts.userId, userId)));

  return requireEmailDraftForUser(draftId, userId);
}

export async function cancelEmailDraft(
  draftId: string,
  userId: string
): Promise<EmailDraft> {
  const existing = await requireEmailDraftForUser(draftId, userId);

  if (existing.status === "sent") {
    throw new EmailDraftError("INVALID_STATE", "Brouillon déjà envoyé.");
  }

  const now = new Date().toISOString();
  const db = getDb();

  await db
    .update(emailDrafts)
    .set({ status: "cancelled", updatedAt: now })
    .where(and(eq(emailDrafts.id, draftId), eq(emailDrafts.userId, userId)));

  return requireEmailDraftForUser(draftId, userId);
}

export async function markEmailDraftSent(
  draftId: string,
  userId: string
): Promise<EmailDraft> {
  const existing = await requireEmailDraftForUser(draftId, userId);

  if (existing.status === "sent") {
    return existing;
  }

  if (existing.status !== "validated") {
    throw new EmailDraftError(
      "INVALID_STATE",
      "Seuls les brouillons validés peuvent être marqués comme envoyés."
    );
  }

  const now = new Date().toISOString();
  const db = getDb();

  await db
    .update(emailDrafts)
    .set({ status: "sent", updatedAt: now })
    .where(and(eq(emailDrafts.id, draftId), eq(emailDrafts.userId, userId)));

  // Mark chat attachments as attached once the email is sent
  const ids = parseAttachmentIds(existing.attachmentIdsJson);
  if (ids.length > 0) {
    await db
      .update(attachments)
      .set({ status: "attached" })
      .where(inArray(attachments.id, ids));
  }

  return requireEmailDraftForUser(draftId, userId);
}
