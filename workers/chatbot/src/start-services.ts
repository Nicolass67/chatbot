import { hasCloudflareAccessJwt } from "./access";
import {
  bootRequestTtlSeconds,
  createBootRequest,
} from "./boot-request";

export interface StartServicesEnv {
  BOOT_KV: KVNamespace;
  BOOT_REQUEST_TTL_SECONDS?: string;
}

function json(data: unknown, status = 200): Response {
  return Response.json(data, { status });
}

/** Crée une demande de démarrage KV sans Wake-on-LAN (PC déjà allumé). */
export async function handleStartServices(
  request: Request,
  env: StartServicesEnv
): Promise<Response> {
  if (!hasCloudflareAccessJwt(request)) {
    return json(
      { ok: false, error: "access_required", message: "Authentification requise" },
      401
    );
  }

  try {
    const ttlSeconds = bootRequestTtlSeconds(env);
    const bootRequest = await createBootRequest(env.BOOT_KV, ttlSeconds, "start");
    return json({
      ok: true,
      message: "Demande de démarrage enregistrée",
      bootRequestId: bootRequest.requestId,
      bootRequestExpiresAt: bootRequest.expiresAt,
    });
  } catch {
    return json(
      {
        ok: false,
        error: "boot_request_failed",
        message: "Impossible d'enregistrer la demande de démarrage",
      },
      503
    );
  }
}
