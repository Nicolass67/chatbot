export const runtime = "nodejs";

import { getEnv } from "@/lib/config/env";
import { getCachedSearxngHealth } from "@/lib/tools/web-search/searxng-health";

export async function GET() {
  try {
    const env = getEnv();
    const searxng = await getCachedSearxngHealth();

    return Response.json({
      status: searxng.status,
      url: searxng.url,
      message: searxng.message,
      checkedAt: searxng.checkedAt,
      httpStatus: searxng.httpStatus,
      resultCount: searxng.resultCount,
      webSearchEnabled: env.WEB_SEARCH_ENABLED,
      provider: env.WEB_SEARCH_PROVIDER,
    });
  } catch (error) {
    return Response.json(
      {
        status: "unavailable",
        message:
          error instanceof Error ? error.message : "Erreur health check Web",
        webSearchEnabled: false,
      },
      { status: 500 }
    );
  }
}
