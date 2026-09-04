import fs from "node:fs";
import type { Attachment } from "@/lib/db/schema";
import type { ChatMessage, MessageContentPart } from "@/lib/runtime/types";

export function readImageAsDataUrl(
  localPath: string,
  mimeType: string
): string {
  const buffer = fs.readFileSync(localPath);
  const base64 = buffer.toString("base64");
  return `data:${mimeType};base64,${base64}`;
}

export function buildMultimodalUserMessage(
  text: string,
  imageAttachments: Attachment[]
): ChatMessage {
  const parts: MessageContentPart[] = [];

  if (text.trim()) {
    parts.push({ type: "text", text: text.trim() });
  }

  for (const img of imageAttachments) {
    parts.push({
      type: "image_url",
      image_url: {
        url: readImageAsDataUrl(img.localPath, img.mimeType),
      },
    });
  }

  if (parts.length === 0) {
    parts.push({ type: "text", text: "" });
  }

  return { role: "user", content: parts };
}

export function isMultimodalContent(
  content: ChatMessage["content"]
): content is MessageContentPart[] {
  return Array.isArray(content);
}

export function serializeContentForStorage(
  text: string,
  attachmentIds: string[]
): string {
  if (attachmentIds.length === 0) return text;
  return JSON.stringify({ text, attachmentIds });
}

export function parseStoredMessageContent(content: string): {
  text: string;
  attachmentIds: string[];
} {
  if (!content.startsWith("{")) {
    return { text: content, attachmentIds: [] };
  }
  try {
    const parsed = JSON.parse(content) as {
      text?: string;
      attachmentIds?: string[];
    };
    return {
      text: parsed.text ?? "",
      attachmentIds: parsed.attachmentIds ?? [],
    };
  } catch {
    return { text: content, attachmentIds: [] };
  }
}
