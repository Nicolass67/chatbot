import { getMailThread } from "@/lib/mail/service";
import { cleanPlainText } from "@/lib/mail/html-utils";
import { resolveFileReference } from "@/lib/files/resolve";
import { getFileRoot } from "@/lib/files/roots";
import { FilesError } from "@/lib/files/types";
import {
  extractTextFromFile,
  guessMimeFromFilename,
} from "@/lib/documents/extract";
import type { NormalizedEmailThread } from "@/lib/integrations/email/types";

/**
 * ACTIVE CONTEXT = USER CONTEXT HINT (not authorization).
 * Client may suggest ids; server always resolve → auth → policy → retrieve.
 */

export type ActiveContextHint = {
  fileId?: string;
  mailThreadId?: string;
  rootId?: string;
  label?: string;
  /** Brouillon mail ouvert dans l’UI (réécriture in-place). */
  draftId?: string;
};

export type ResolvedActiveContext = {
  hint: ActiveContextHint;
  resolved: boolean;
  ignoredReason?: string;
  /** Safe labels for LLM / retrieval — never absolute Windows paths */
  entityLabels: string[];
  file?: {
    fileId: string;
    name: string;
    rootId: string;
    relativePath: string;
    /** Contenu extrait pour le LLM (tronqué). */
    contentForLlm?: string;
  };
  mail?: {
    threadId: string;
    /** Id du dernier message — pour inReplyToMessageId sur email_create_draft. */
    lastMessageId?: string;
    subject?: string;
    /** Contenu lisible pour le LLM (dernier message + contexte). */
    bodyForLlm?: string;
    from?: string;
    date?: string;
    attachmentNames?: string[];
    recipients?: string[];
  };
  root?: {
    rootId: string;
    label: string;
  };
};

const BODY_MAX = 8_000;

/** Formate un thread mail pour injection contexte LLM (corps inclus). */
export function formatMailThreadBodyForLlm(
  thread: NormalizedEmailThread,
  maxChars = BODY_MAX
): string {
  const lastIndex = thread.messages.length - 1;
  const parts = thread.messages.map((m, index) => {
    const from = m.from.name
      ? `${m.from.name} <${m.from.email}>`
      : m.from.email;
    const to = (m.to ?? [])
      .map((r) => (r.name ? `${r.name} <${r.email}>` : r.email))
      .join(", ");
    const body =
      cleanPlainText(m.bodyText).slice(0, 3500) ||
      cleanPlainText(m.bodyHtml ?? "").slice(0, 3500) ||
      cleanPlainText(m.snippet).slice(0, 500);
    const atts = (m.attachments ?? [])
      .map((a) => a.filename || a.id)
      .filter(Boolean);
    const label =
      index === lastIndex
        ? `--- DERNIER MESSAGE ${m.id} ---`
        : `--- Message antérieur ${m.id} ---`;
    return `${label}
De: ${from}
À: ${to || "(n/a)"}
Date: ${m.date}
Objet: ${m.subject}
${atts.length ? `Pièces jointes: ${atts.join(", ")}\n` : ""}
${body || "(contenu non disponible)"}`;
  });
  const joined = parts.join("\n\n");
  if (joined.length <= maxChars) return joined;
  return `${joined.slice(0, maxChars)}…`;
}

export async function resolveActiveContext(input: {
  userId: string;
  hint?: ActiveContextHint | null;
}): Promise<ResolvedActiveContext> {
  const hint = input.hint ?? {};
  const hasAny =
    Boolean(hint.fileId?.trim()) ||
    Boolean(hint.mailThreadId?.trim()) ||
    Boolean(hint.rootId?.trim());

  if (!hasAny) {
    return {
      hint,
      resolved: false,
      entityLabels: hint.label?.trim() ? [hint.label.trim()] : [],
    };
  }

  const entityLabels: string[] = [];
  if (hint.label?.trim()) entityLabels.push(hint.label.trim());

  let file: ResolvedActiveContext["file"];
  let mail: ResolvedActiveContext["mail"];
  let root: ResolvedActiveContext["root"];
  const ignoreReasons: string[] = [];

  if (hint.fileId?.trim()) {
    try {
      const resolved = await resolveFileReference(
        input.userId,
        hint.fileId.trim(),
        { requireExpose: true }
      );
      const name =
        resolved.displayName ||
        resolved.relativePath.split("/").filter(Boolean).pop() ||
        resolved.relativePath;
      file = {
        fileId: resolved.fileId,
        name,
        rootId: resolved.rootId,
        relativePath: resolved.relativePath,
      };
      try {
        if (!resolved.isDirectory && resolved.absolutePath) {
          const mime = guessMimeFromFilename(name);
          const text = await extractTextFromFile(
            resolved.absolutePath,
            mime,
            name
          );
          const trimmed = text.trim();
          if (trimmed) {
            file.contentForLlm =
              trimmed.length > 8_000
                ? `${trimmed.slice(0, 8_000)}…`
                : trimmed;
          }
        }
      } catch {
        /* extraction best-effort */
      }
      entityLabels.push(name);
    } catch (err) {
      const code = err instanceof FilesError ? err.code : "FORBIDDEN";
      ignoreReasons.push(`file:${code}`);
    }
  }

  if (hint.rootId?.trim()) {
    const r = await getFileRoot(input.userId, hint.rootId.trim());
    if (r?.enabled) {
      root = { rootId: r.id, label: r.label };
      entityLabels.push(r.label);
    } else {
      ignoreReasons.push("root:denied");
    }
  }

  if (hint.mailThreadId?.trim()) {
    try {
      const thread = await getMailThread(
        input.userId,
        hint.mailThreadId.trim()
      );
      const last = thread.messages[thread.messages.length - 1];
      const from = last?.from
        ? last.from.name
          ? `${last.from.name} <${last.from.email}>`
          : last.from.email
        : undefined;
      const recipients = (last?.to ?? [])
        .map((r) => (r.name ? `${r.name} <${r.email}>` : r.email))
        .filter(Boolean);
      const attachmentNames = thread.messages
        .flatMap((m) => m.attachments ?? [])
        .map((a) => a.filename || a.id)
        .filter(Boolean)
        .slice(0, 12);
      mail = {
        threadId: thread.id,
        lastMessageId: last?.id,
        subject: thread.subject || last?.subject,
        bodyForLlm: formatMailThreadBodyForLlm(thread),
        from,
        date: last?.date,
        attachmentNames,
        recipients,
      };
      if (mail.subject) entityLabels.push(mail.subject);
    } catch {
      ignoreReasons.push("mail:unavailable");
    }
  }

  const resolved = Boolean(file || mail || root);
  return {
    hint: {
      fileId: file?.fileId,
      mailThreadId: mail?.threadId,
      rootId: root?.rootId ?? hint.rootId,
      label: hint.label,
      draftId: hint.draftId?.trim() || undefined,
    },
    resolved,
    ignoredReason: !resolved
      ? ignoreReasons.join(",") || "unresolved"
      : ignoreReasons.length > 0
        ? ignoreReasons.join(",")
        : undefined,
    entityLabels: [...new Set(entityLabels)].slice(0, 6),
    file,
    mail,
    root,
  };
}

/** Safe block for system prompt — no absolute paths. Includes mail body when present. */
export function formatActiveContextBlock(
  ctx: ResolvedActiveContext
): string | null {
  if (!ctx.resolved) return null;
  const lines: string[] = [];
  if (ctx.hint.draftId?.trim()) {
    lines.push(
      `Brouillon ouvert: draftId=${ctx.hint.draftId.trim()} — pour réécrire, appelle email_create_draft (le serveur met à jour CE brouillon et conserve threadId / inReplyTo).`
    );
  }
  if (ctx.file) {
    lines.push(
      `Fichier actif: ${ctx.file.name} (fileId=${ctx.file.fileId}, path relatif=${ctx.file.relativePath})`
    );
    if (ctx.file.contentForLlm) {
      lines.push(
        `<file_context untrusted="true">\n${ctx.file.contentForLlm}\n</file_context>`
      );
    }
  }
  if (ctx.mail) {
    lines.push(
      `Fil mail actif: ${ctx.mail.subject ?? ctx.mail.threadId} (threadId=${ctx.mail.threadId}${
        ctx.mail.lastMessageId
          ? `, lastMessageId=${ctx.mail.lastMessageId}`
          : ""
      })`
    );
    lines.push(
      `Pour répondre à CE fil : passe TOUJOURS threadId=${ctx.mail.threadId}${
        ctx.mail.lastMessageId
          ? ` et inReplyToMessageId=${ctx.mail.lastMessageId}`
          : ""
      } à email_create_draft.`
    );
    if (ctx.mail.from) lines.push(`Expéditeur: ${ctx.mail.from}`);
    if (ctx.mail.recipients?.length) {
      lines.push(`Destinataires: ${ctx.mail.recipients.join(", ")}`);
    }
    if (ctx.mail.date) lines.push(`Date: ${ctx.mail.date}`);
    if (ctx.mail.attachmentNames?.length) {
      lines.push(`Pièces jointes: ${ctx.mail.attachmentNames.join(", ")}`);
    }
    if (ctx.mail.bodyForLlm) {
      lines.push(
        `<email_context untrusted="true">\n${ctx.mail.bodyForLlm}\n</email_context>`
      );
    }
  }
  if (ctx.root) {
    lines.push(`Source Files active: ${ctx.root.label} (rootId=${ctx.root.rootId})`);
  }
  if (lines.length === 0) return null;
  return `<active_context>\n${lines.join("\n")}\n</active_context>`;
}
