import { hasCloudflareAccessJwt } from "./access";
import {
  createBootRequest,
  bootRequestTtlSeconds,
} from "./boot-request";
import {
  diagnosticResponseBody,
  freeboxWakePc,
  FreeboxStepError,
  type FreeboxConfig,
} from "./freebox";

export interface WakeEnv {
  FREEBOX_APP_TOKEN?: string;
  FREEBOX_APP_ID: string;
  FREEBOX_API_DOMAIN: string;
  FREEBOX_HTTPS_PORT: string;
  FREEBOX_WOL_MAC: string;
  BOOT_KV: KVNamespace;
  BOOT_REQUEST_TTL_SECONDS?: string;
}

function json(data: unknown, status = 200): Response {
  return Response.json(data, { status });
}

function buildFreeboxConfig(env: WakeEnv): FreeboxConfig | null {
  if (!env.FREEBOX_APP_TOKEN?.trim()) {
    return null;
  }
  if (
    !env.FREEBOX_APP_ID?.trim() ||
    !env.FREEBOX_API_DOMAIN?.trim() ||
    !env.FREEBOX_HTTPS_PORT?.trim() ||
    !env.FREEBOX_WOL_MAC?.trim()
  ) {
    return null;
  }

  return {
    apiDomain: env.FREEBOX_API_DOMAIN.trim(),
    httpsPort: env.FREEBOX_HTTPS_PORT.trim(),
    appId: env.FREEBOX_APP_ID.trim(),
    appToken: env.FREEBOX_APP_TOKEN.trim(),
    wolMac: env.FREEBOX_WOL_MAC.trim(),
  };
}

export async function handleWake(
  request: Request,
  env: WakeEnv,
  fetchFn: typeof fetch = fetch
): Promise<Response> {
  if (!hasCloudflareAccessJwt(request)) {
    return json(
      { ok: false, error: "access_required", message: "Authentification requise" },
      401
    );
  }

  const config = buildFreeboxConfig(env);
  if (!config) {
    return json(
      {
        ok: false,
        error: "configuration_missing",
        message: "Configuration Freebox incomplète",
      },
      503
    );
  }

  try {
    const ttlSeconds = bootRequestTtlSeconds(env);
    const bootRequest = await createBootRequest(env.BOOT_KV, ttlSeconds, "start");
    await freeboxWakePc(fetchFn, config);
    return json({
      ok: true,
      message: "Wake-on-LAN envoyé à la Freebox",
      bootRequestId: bootRequest.requestId,
      bootRequestExpiresAt: bootRequest.expiresAt,
    });
  } catch (error) {
    if (error instanceof FreeboxStepError) {
      return json(diagnosticResponseBody(error.diagnostic), 502);
    }

    return json(
      {
        ok: false,
        step: "freebox",
        status: 502,
        error_code: "network_error",
        msg: "Impossible de joindre la Freebox",
      },
      502
    );
  }
}
