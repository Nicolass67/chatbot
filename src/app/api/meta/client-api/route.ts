export const runtime = "nodejs";

import fs from "node:fs";
import path from "node:path";

/**
 * Métadonnées Client Surface — versions + capabilities.
 * Télémétrie client via headers X-Client / X-App-Version (jamais authz).
 */
export async function GET(request: Request) {
  const versionPath = path.join(process.cwd(), "contracts", "VERSION");
  let contractsVersion = 1;
  try {
    const raw = fs.readFileSync(versionPath, "utf8").trim();
    const n = Number(raw);
    if (Number.isFinite(n)) contractsVersion = n;
  } catch {
    /* default 1 */
  }

  const client = request.headers.get("x-client")?.trim() || undefined;
  const appVersion = request.headers.get("x-app-version")?.trim() || undefined;

  return Response.json(
    {
      apiVersion: 1,
      chatEventsVersion: 1,
      contractsVersion,
      features: {
        chatSse: true,
        mail: true,
        files: true,
        memories: true,
        webSearch: true,
        appSessionBearer: true,
      },
      telemetry: {
        acceptedHeaders: ["X-Client", "X-App-Version", "X-API-Version"],
        note: "Telemetry only — never authorization",
      },
      observed: {
        client: client ?? null,
        appVersion: appVersion ?? null,
      },
    },
    {
      headers: {
        "X-API-Version": "1",
        "X-Chat-Events-Version": "1",
        "Cache-Control": "no-store",
      },
    }
  );
}
