import { offlineWakePageResponse } from "./offline-page";

export type BackendState = "online" | "offline";

const HEALTH_URL = "http://127.0.0.1:3000/api/health";

export interface BackendEnv {
  PRIVATE_API: Fetcher;
  /** Bearer pour GET /api/health quand CF Access est actif côté origin. */
  HEALTH_CHECK_TOKEN?: string;
}

interface HealthPayload {
  checks?: {
    nextjs?: { status?: string };
  };
}

function isBackendOnlineResponse(response: Response, payload?: HealthPayload): boolean {
  if (response.ok) return true;
  return payload?.checks?.nextjs?.status === "ok";
}

/** Teste si Next.js répond via le VPC — ne déclenche jamais de WoL. */
export async function checkBackendState(
  env: BackendEnv,
  fetchOverride?: typeof fetch
): Promise<BackendState> {
  const fetchFn =
    fetchOverride ??
    ((input: RequestInfo | URL, init?: RequestInit) =>
      env.PRIVATE_API.fetch(input, init));

  try {
    const headers = new Headers();
    const healthToken = env.HEALTH_CHECK_TOKEN?.trim();
    if (healthToken) {
      headers.set("Authorization", `Bearer ${healthToken}`);
    }
    const response = await fetchFn(HEALTH_URL, { method: "GET", headers });
    const contentType = response.headers.get("content-type") ?? "";

    if (contentType.includes("application/json")) {
      const payload = (await response.json()) as HealthPayload;
      return isBackendOnlineResponse(response, payload) ? "online" : "offline";
    }

    return response.ok ? "online" : "offline";
  } catch {
    return "offline";
  }
}

export function backendOfflineProxyResponse(
  request: Request,
  acceptJson = wantsJson(request)
): Response {
  const payload = {
    error: "backend_offline",
    message: "Le PC ou Next.js est indisponible.",
    status_url: "/status",
    wake_url: "/wake",
  };

  if (acceptJson) {
    return Response.json(payload, {
      status: 503,
      headers: { "Cache-Control": "no-store" },
    });
  }

  return offlineWakePageResponse();
}

export function wantsJson(request: Request): boolean {
  const accept = request.headers.get("Accept") ?? "";
  if (accept.includes("application/json")) return true;
  const pathname = new URL(request.url).pathname;
  return pathname.startsWith("/api/");
}
