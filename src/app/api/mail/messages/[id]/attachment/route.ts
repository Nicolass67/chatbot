export const runtime = "nodejs";

import { withAuth } from "@/lib/auth/types";
import { apiAuthGuard } from "@/lib/auth/api-auth";
import { getEmailProvider } from "@/lib/integrations/email";
import {
  EmailNotConnectedError,
  EmailProviderError,
} from "@/lib/integrations/email/types";
import { isEmailFeatureEnabled } from "@/lib/integrations/oauth";
import { apiErrorResponse } from "@/lib/http/api-error";

function sanitizeFilename(filename: string): string {
  return filename.replace(/[\r\n"]/g, "_").slice(0, 180) || "attachment";
}

/**
 * Télécharge une pièce jointe Gmail.
 * attachmentId passé en query (les IDs Gmail sont trop longs / fragiles en segment d'URL).
 */
export const GET = withAuth(
  apiAuthGuard,
  async (
    request,
    auth,
    ctx: { params: Promise<{ id: string }> }
  ) => {
    if (!isEmailFeatureEnabled()) {
      return apiErrorResponse("FEATURE_DISABLED", "Email désactivé");
    }

    const { id: messageId } = await ctx.params;
    const userId = auth.userId ?? "local";
    const url = new URL(request.url);
    const attachmentId = url.searchParams.get("attachmentId")?.trim();
    const asDownload = url.searchParams.get("download") === "1";

    if (!attachmentId) {
      return Response.json(
        { error: "attachmentId requis" },
        { status: 400 }
      );
    }

    try {
      const provider = await getEmailProvider(userId);
      const message = await provider.getMessage(messageId);
      const meta =
        message.attachments.find((a) => a.id === attachmentId) ??
        message.attachments.find(
          (a) =>
            a.filename === url.searchParams.get("filename") &&
            Number(url.searchParams.get("size") ?? -1) === a.sizeBytes
        );

      // Même si les métadonnées ne matchent pas (ID Gmail parfois instable),
      // on tente le téléchargement direct avec l'ID fourni par le client.
      const file = await provider.getAttachment(messageId, attachmentId);
      const filename = sanitizeFilename(
        meta?.filename ||
          url.searchParams.get("filename") ||
          "piece-jointe"
      );
      const mimeType =
        meta?.mimeType ||
        url.searchParams.get("mimeType") ||
        "application/octet-stream";
      const disposition = asDownload ? "attachment" : "inline";

      return new Response(new Uint8Array(file.data), {
        headers: {
          "Content-Type": mimeType,
          "Content-Length": String(file.size),
          "Content-Disposition": `${disposition}; filename="${filename}"`,
          "Cache-Control": "private, max-age=300",
        },
      });
    } catch (error) {
      if (error instanceof EmailNotConnectedError) {
        return apiErrorResponse("EMAIL_NOT_CONNECTED", error.message);
      }
      if (error instanceof EmailProviderError) {
        return Response.json(
          { error: error.message, code: error.code },
          { status: error.code === "NOT_FOUND" ? 404 : 502 }
        );
      }
      throw error;
    }
  }
);
