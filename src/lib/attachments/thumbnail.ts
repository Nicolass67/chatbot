import fs from "node:fs";
import path from "node:path";

const THUMB_MAX = 1200;
const THUMB_MIN = 64;

export function clampThumbWidth(raw: number | null): number | null {
  if (raw == null || !Number.isFinite(raw) || raw <= 0) return null;
  return Math.min(THUMB_MAX, Math.max(THUMB_MIN, Math.round(raw)));
}

/** Miniatures JPEG cachees à côté du fichier source (évite de retraverser le tunnel en full-res). */
export async function getOrCreateAttachmentThumb(
  localPath: string,
  mimeType: string,
  width: number
): Promise<{ buffer: Buffer; mimeType: string } | null> {
  if (!mimeType.startsWith("image/")) return null;

  const thumbPath = `${localPath}.thumb.${width}.jpg`;
  try {
    if (fs.existsSync(thumbPath)) {
      const stSrc = fs.statSync(localPath);
      const stThumb = fs.statSync(thumbPath);
      if (stThumb.mtimeMs >= stSrc.mtimeMs && stThumb.size > 0) {
        return { buffer: fs.readFileSync(thumbPath), mimeType: "image/jpeg" };
      }
    }
  } catch {
    // regenerate below
  }

  try {
    const sharp = (await import("sharp")).default;
    const input = fs.readFileSync(localPath);
    const buffer = await sharp(input)
      .rotate()
      .resize({
        width,
        height: width,
        fit: "inside",
        withoutEnlargement: true,
      })
      .jpeg({ quality: 72, mozjpeg: true })
      .toBuffer();

    try {
      fs.mkdirSync(path.dirname(thumbPath), { recursive: true });
      fs.writeFileSync(thumbPath, buffer);
    } catch {
      // cache miss ok — still return buffer
    }

    return { buffer, mimeType: "image/jpeg" };
  } catch {
    return null;
  }
}
