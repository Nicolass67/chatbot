import { getMailThread } from "@/lib/mail/service";
import { resolveFileReference } from "@/lib/files/resolve";
import { getFileRoot } from "@/lib/files/roots";
import { FilesError } from "@/lib/files/types";

/**
 * ACTIVE CONTEXT = USER CONTEXT HINT (not authorization).
 * Client may suggest ids; server always resolve → auth → policy → retrieve.
 */

export type ActiveContextHint = {
  fileId?: string;
  mailThreadId?: string;
  rootId?: string;
  label?: string;
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
  };
  mail?: {
    threadId: string;
    subject?: string;
  };
  root?: {
    rootId: string;
    label: string;
  };
};

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
      mail = {
        threadId: thread.id,
        subject: thread.subject || thread.messages[0]?.subject,
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

/** Safe block for system prompt — no absolute paths. */
export function formatActiveContextBlock(
  ctx: ResolvedActiveContext
): string | null {
  if (!ctx.resolved) return null;
  const lines: string[] = [];
  if (ctx.file) {
    lines.push(
      `Fichier actif: ${ctx.file.name} (fileId=${ctx.file.fileId}, path relatif=${ctx.file.relativePath})`
    );
  }
  if (ctx.mail) {
    lines.push(
      `Fil mail actif: ${ctx.mail.subject ?? ctx.mail.threadId} (threadId=${ctx.mail.threadId})`
    );
  }
  if (ctx.root) {
    lines.push(`Source Files active: ${ctx.root.label} (rootId=${ctx.root.rootId})`);
  }
  if (lines.length === 0) return null;
  return `<active_context>\n${lines.join("\n")}\n</active_context>`;
}
