import { hasCloudflareAccessJwt } from "./access";
import {
  bootRequestTtlSeconds,
  createBootRequest,
} from "./boot-request";

export interface RestartServicesEnv {
  BOOT_KV: KVNamespace;
  BOOT_REQUEST_TTL_SECONDS?: string;
}

function json(data: unknown, status = 200): Response {
  return Response.json(data, { status });
}

/** Crée une demande de redémarrage KV (arrêt propre + relance). */
export async function handleRestartServices(
  request: Request,
  env: RestartServicesEnv
): Promise<Response> {
  if (!hasCloudflareAccessJwt(request)) {
    return json(
      { ok: false, error: "access_required", message: "Authentification requise" },
      401
    );
  }

  try {
    const ttlSeconds = bootRequestTtlSeconds(env);
    const bootRequest = await createBootRequest(env.BOOT_KV, ttlSeconds, "restart");
    return json({
      ok: true,
      message: "Demande de redémarrage enregistrée",
      action: "restart",
      bootRequestId: bootRequest.requestId,
      bootRequestExpiresAt: bootRequest.expiresAt,
    });
  } catch {
    return json(
      {
        ok: false,
        error: "boot_request_failed",
        message: "Impossible d'enregistrer la demande de redémarrage",
      },
      503
    );
  }
}
