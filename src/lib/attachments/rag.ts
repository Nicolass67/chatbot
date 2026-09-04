import { getSqlite } from "@/lib/db";
import type { Attachment } from "@/lib/db/schema";

export interface DocumentPassage {
  attachmentId: string;
  filename: string;
  chunkIndex: number;
  content: string;
  score: number;
}

export interface RagSearchOptions {
  conversationId: string;
  attachmentIds: string[];
  query: string;
  limit?: number;
}

/** FTS5 keyword search — abstraction point for future embedding retrieval. */
export async function searchDocumentPassages(
  options: RagSearchOptions
): Promise<DocumentPassage[]> {
  const { conversationId, attachmentIds, query, limit = 5 } = options;
  if (!query.trim() || attachmentIds.length === 0) return [];

  const sqlite = getSqlite();
  const placeholders = attachmentIds.map(() => "?").join(",");
  const ftsQuery = query
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => `"${w.replace(/"/g, "")}"`)
    .join(" OR ");

  const rows = sqlite
    .prepare(
      `
      SELECT
        dc.id,
        dc.attachment_id as attachmentId,
        dc.chunk_index as chunkIndex,
        dc.content,
        bm25(document_chunks_fts) as score,
        a.filename
      FROM document_chunks_fts fts
      JOIN document_chunks dc ON dc.rowid = fts.rowid
      JOIN attachments a ON a.id = dc.attachment_id
      WHERE document_chunks_fts MATCH ?
        AND dc.conversation_id = ?
        AND dc.attachment_id IN (${placeholders})
      ORDER BY score
      LIMIT ?
    `
    )
    .all(ftsQuery, conversationId, ...attachmentIds, limit) as Array<{
    attachmentId: string;
    chunkIndex: number;
    content: string;
    score: number;
    filename: string;
  }>;

  return rows.map((r) => ({
    attachmentId: r.attachmentId,
    filename: r.filename,
    chunkIndex: r.chunkIndex,
    content: r.content,
    score: r.score,
  }));
}

export function formatPassagesForContext(passages: DocumentPassage[]): string {
  if (passages.length === 0) return "";
  const blocks = passages.map(
    (p, i) =>
      `[Document ${i + 1}: ${p.filename} §${p.chunkIndex + 1}]\n${p.content}`
  );
  return `Passages extraits des documents joints :\n\n${blocks.join("\n\n")}`;
}

export async function buildDocumentContext(
  conversationId: string,
  docs: Attachment[],
  userMessage: string,
  directInjectMaxChars: number
): Promise<string> {
  const documentAttachments = docs.filter((d) => d.type === "document");
  if (documentAttachments.length === 0) return "";

  const parts: string[] = [];

  for (const doc of documentAttachments) {
    if (doc.extractedCharCount > 0 && doc.extractedCharCount <= directInjectMaxChars) {
      const sqlite = getSqlite();
      const chunks = sqlite
        .prepare(
          `SELECT content FROM document_chunks WHERE attachment_id = ? ORDER BY chunk_index`
        )
        .all(doc.id) as Array<{ content: string }>;
      const full = chunks.map((c) => c.content).join("\n\n");
      parts.push(`[Document complet: ${doc.filename}]\n${full}`);
    }
  }

  const longDocIds = documentAttachments
    .filter((d) => d.extractedCharCount > directInjectMaxChars)
    .map((d) => d.id);

  if (longDocIds.length > 0) {
    const passages = await searchDocumentPassages({
      conversationId,
      attachmentIds: longDocIds,
      query: userMessage,
      limit: 6,
    });
    const ragBlock = formatPassagesForContext(passages);
    if (ragBlock) parts.push(ragBlock);
  }

  return parts.join("\n\n");
}
