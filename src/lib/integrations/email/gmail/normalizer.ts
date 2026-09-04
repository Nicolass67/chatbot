import type { gmail_v1 } from "googleapis";
import type {
  EmailAddress,
  EmailAttachmentMeta,
  NormalizedEmailMessage,
  NormalizedEmailThread,
} from "../types";
import { decodeHtmlEntities, htmlToPlainText } from "@/lib/mail/html-utils";

function decodeBase64Url(data: string): string {
  const normalized = data.replace(/-/g, "+").replace(/_/g, "/");
  return Buffer.from(normalized, "base64").toString("utf8");
}

function parseEmailAddress(raw: string): EmailAddress {
  const match = raw.match(/^(?:"?([^"]*)"?\s)?<?([^>]+@[^>]+)>?$/);
  if (!match) {
    return { email: raw.trim() };
  }
  const name = match[1]?.trim();
  const email = match[2]?.trim() ?? raw.trim();
  return name ? { email, name } : { email };
}

function parseAddressList(raw: string | undefined): EmailAddress[] {
  if (!raw?.trim()) return [];
  return raw.split(",").map((part) => parseEmailAddress(part.trim()));
}

function getHeader(
  headers: gmail_v1.Schema$MessagePartHeader[] | undefined,
  name: string
): string | undefined {
  const found = headers?.find(
    (h) => h.name?.toLowerCase() === name.toLowerCase()
  );
  return found?.value ?? undefined;
}

function extractBodies(part: gmail_v1.Schema$MessagePart | undefined): {
  bodyText: string;
  bodyHtml?: string;
} {
  if (!part) return { bodyText: "" };

  let bodyText = "";
  let bodyHtml: string | undefined;

  const visit = (node: gmail_v1.Schema$MessagePart) => {
    const mimeType = node.mimeType ?? "";
    if (node.body?.data) {
      const decoded = decodeBase64Url(node.body.data);
      if (mimeType === "text/plain" && !bodyText) {
        bodyText = decoded;
      } else if (mimeType === "text/html" && !bodyHtml) {
        bodyHtml = decoded;
      }
    }
    for (const child of node.parts ?? []) {
      visit(child);
    }
  };

  visit(part);
  if (!bodyText && bodyHtml) {
    bodyText = htmlToPlainText(bodyHtml);
  }
  return { bodyText, bodyHtml };
}

function extractAttachments(
  part: gmail_v1.Schema$MessagePart | undefined
): EmailAttachmentMeta[] {
  const attachments: EmailAttachmentMeta[] = [];

  const visit = (node: gmail_v1.Schema$MessagePart) => {
    if (node.filename && node.body?.attachmentId) {
      attachments.push({
        id: node.body.attachmentId,
        filename: node.filename,
        mimeType: node.mimeType ?? "application/octet-stream",
        sizeBytes: node.body.size ?? 0,
      });
    }
    for (const child of node.parts ?? []) {
      visit(child);
    }
  };

  if (part) visit(part);
  return attachments;
}

export function normalizeGmailMessage(
  message: gmail_v1.Schema$Message
): NormalizedEmailMessage {
  const headers = message.payload?.headers;
  const { bodyText, bodyHtml } = extractBodies(message.payload ?? undefined);
  const attachments = extractAttachments(message.payload ?? undefined);
  const labelIds = message.labelIds ?? [];

  return {
    id: message.id ?? "",
    threadId: message.threadId ?? "",
    from: parseEmailAddress(getHeader(headers, "From") ?? "unknown@unknown"),
    to: parseAddressList(getHeader(headers, "To")),
    cc: parseAddressList(getHeader(headers, "Cc")),
    bcc: parseAddressList(getHeader(headers, "Bcc")),
    subject: decodeHtmlEntities(getHeader(headers, "Subject") ?? "(sans objet)"),
    date: getHeader(headers, "Date") ?? new Date().toISOString(),
    snippet: decodeHtmlEntities(message.snippet ?? ""),
    bodyText,
    bodyHtml,
    labelIds,
    hasAttachments: attachments.length > 0,
    attachments,
    isUnread: labelIds.includes("UNREAD"),
  };
}

export function normalizeGmailThread(
  thread: gmail_v1.Schema$Thread
): NormalizedEmailThread {
  const messages = (thread.messages ?? []).map(normalizeGmailMessage);
  const participantMap = new Map<string, EmailAddress>();

  for (const message of messages) {
    const add = (addr: EmailAddress) => {
      if (addr.email) participantMap.set(addr.email.toLowerCase(), addr);
    };
    add(message.from);
    for (const addr of [...message.to, ...message.cc]) add(addr);
  }

  const subject =
    messages.find((m) => m.subject && m.subject !== "(sans objet)")?.subject ??
    messages[0]?.subject ??
    "(sans objet)";

  return {
    id: thread.id ?? "",
    subject,
    messages,
    participants: [...participantMap.values()],
  };
}

export function buildGmailRawMessage(input: {
  to: string[];
  cc?: string[];
  bcc?: string[];
  subject: string;
  bodyText: string;
  inReplyToHeader?: string;
  referencesHeader?: string;
  attachments?: Array<{
    filename: string;
    mimeType: string;
    contentBase64: string;
  }>;
}): string {
  const headerLines = [
    `To: ${input.to.join(", ")}`,
    input.cc?.length ? `Cc: ${input.cc.join(", ")}` : null,
    input.bcc?.length ? `Bcc: ${input.bcc.join(", ")}` : null,
    `Subject: ${encodeRfc2047Subject(input.subject)}`,
    input.inReplyToHeader ? `In-Reply-To: ${input.inReplyToHeader}` : null,
    input.referencesHeader ? `References: ${input.referencesHeader}` : null,
    "MIME-Version: 1.0",
  ].filter((line): line is string => line != null);

  const attachments = input.attachments ?? [];
  if (attachments.length === 0) {
    const lines = [
      ...headerLines,
      "Content-Type: text/plain; charset=UTF-8",
      "Content-Transfer-Encoding: base64",
      "",
      wrapBase64(Buffer.from(input.bodyText, "utf8").toString("base64")),
    ];
    return Buffer.from(lines.join("\r\n"), "utf8").toString("base64url");
  }

  const boundary = `boundary_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 10)}`;
  const parts: string[] = [
    ...headerLines,
    `Content-Type: multipart/mixed; boundary="${boundary}"`,
    "",
    `--${boundary}`,
    "Content-Type: text/plain; charset=UTF-8",
    "Content-Transfer-Encoding: base64",
    "",
    wrapBase64(Buffer.from(input.bodyText, "utf8").toString("base64")),
  ];

  for (const file of attachments) {
    const safeName = sanitizeMimeFilename(file.filename);
    const mime = file.mimeType || "application/octet-stream";
    parts.push(
      `--${boundary}`,
      `Content-Type: ${mime}; name="${safeName}"`,
      "Content-Transfer-Encoding: base64",
      `Content-Disposition: attachment; filename="${safeName}"`,
      "",
      wrapBase64(file.contentBase64.replace(/\s+/g, ""))
    );
  }

  parts.push(`--${boundary}--`, "");
  return Buffer.from(parts.join("\r\n"), "utf8").toString("base64url");
}

function wrapBase64(value: string, lineLength = 76): string {
  const compact = value.replace(/\s+/g, "");
  const lines: string[] = [];
  for (let i = 0; i < compact.length; i += lineLength) {
    lines.push(compact.slice(i, i + lineLength));
  }
  return lines.join("\r\n");
}

function sanitizeMimeFilename(filename: string): string {
  return filename.replace(/[\r\n"\\]/g, "_").slice(0, 180) || "fichier";
}

function encodeRfc2047Subject(subject: string): string {
  if (/^[\x20-\x7E]*$/.test(subject)) return subject;
  const encoded = Buffer.from(subject, "utf8").toString("base64");
  return `=?UTF-8?B?${encoded}?=`;
}

export function buildGmailListQuery(params: {
  query?: string;
  after?: string;
}): string | undefined {
  const parts: string[] = [];
  if (params.query?.trim()) parts.push(params.query.trim());
  if (params.after) {
    const date = params.after.slice(0, 10).replace(/-/g, "/");
    parts.push(`after:${date}`);
  }
  return parts.length > 0 ? parts.join(" ") : undefined;
}
