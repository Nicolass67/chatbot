export const runtime = "nodejs";

import { apiErrorResponse } from "@/lib/http/api-error";
import {
  exportConversationJson,
  exportConversationMarkdown,
} from "@/lib/export/conversation";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const format = new URL(request.url).searchParams.get("format") ?? "json";

  try {
    if (format === "md") {
      const md = await exportConversationMarkdown(id);
      return new Response(md, {
        headers: {
          "Content-Type": "text/markdown; charset=utf-8",
          "Content-Disposition": `attachment; filename="conversation-${id}.md"`,
        },
      });
    }

    const data = await exportConversationJson(id);
    return Response.json(data, {
      headers: {
        "Content-Disposition": `attachment; filename="conversation-${id}.json"`,
      },
    });
  } catch {
    return apiErrorResponse("NOT_FOUND", "Conversation introuvable");
  }
}
