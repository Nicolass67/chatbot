export const runtime = "nodejs";

import fs from "node:fs";
import path from "node:path";
import { eq } from "drizzle-orm";
import { getDb } from "@/lib/db";
import { attachments } from "@/lib/db/schema";
import { deleteAttachmentById } from "@/lib/attachments/storage";
import {
  clampThumbWidth,
  getOrCreateAttachmentThumb,
} from "@/lib/attachments/thumbnail";
import { apiErrorResponse } from "@/lib/http/api-error";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const url = new URL(request.url);
  const asDownload = url.searchParams.get("download") === "1";
  const thumbW = clampThumbWidth(
    url.searchParams.has("w")
      ? Number(url.searchParams.get("w"))
      : url.searchParams.get("thumb") === "1"
        ? 360
        : null
  );

  const db = getDb();
  const [row] = await db
    .select()
    .from(attachments)
    .where(eq(attachments.id, id))
    .limit(1);

  if (!row || !fs.existsSync(row.localPath)) {
    return new Response("Not found", { status: 404 });
  }

  const safeName = path.basename(row.filename).replace(/"/g, "");

  if (thumbW) {
    const thumb = await getOrCreateAttachmentThumb(
      row.localPath,
      row.mimeType,
      thumbW
    );
    if (thumb) {
      return new Response(new Uint8Array(thumb.buffer), {
        headers: {
          "Content-Type": thumb.mimeType,
          "Content-Length": String(thumb.buffer.length),
          "Content-Disposition": `inline; filename="${safeName.replace(/\.[^.]+$/, "")}-thumb.jpg"`,
          "Cache-Control": "private, max-age=86400",
          "X-Attachment-Thumb": String(thumbW),
        },
      });
    }
  }

  const buffer = fs.readFileSync(row.localPath);
  const disposition = asDownload ? "attachment" : "inline";
  return new Response(buffer, {
    headers: {
      "Content-Type": row.mimeType,
      "Content-Length": String(buffer.length),
      "Content-Disposition": `${disposition}; filename="${safeName}"`,
      "Cache-Control": "private, max-age=3600",
    },
  });
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const deleted = await deleteAttachmentById(id);
  if (!deleted) {
    return apiErrorResponse("NOT_FOUND", "Introuvable");
  }
  return Response.json({ success: true });
}
