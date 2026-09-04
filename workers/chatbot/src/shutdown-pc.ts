import { hasCloudflareAccessJwt } from "./access";
import {
  bootRequestTtlSeconds,
  createBootRequest,
} from "./boot-request";

export interface ShutdownPcEnv {
  BOOT_KV: KVNamespace;
  BOOT_REQUEST_TTL_SECONDS?: string;
}

function json(data: unknown, status = 200): Response {
  return Response.json(data, { status });
}

/** Crée une demande KV d'extinction PC (consommée par le poll local). */
export async function handleShutdownPc(
  request: Request,
  env: ShutdownPcEnv
): Promise<Response> {
  if (!hasCloudflareAccessJwt(request)) {
    return json(
      { ok: false, error: "access_required", message: "Authentification requise" },
      401
    );
  }

  try {
    const ttlSeconds = bootRequestTtlSeconds(env);
    const bootRequest = await createBootRequest(env.BOOT_KV, ttlSeconds, "shutdown");
    return json({
      ok: true,
      message:
        "Demande d'arrêt enregistrée — le PC s'éteindra sous ~1 minute après prise en charge",
      action: "shutdown",
      bootRequestId: bootRequest.requestId,
      bootRequestExpiresAt: bootRequest.expiresAt,
    });
  } catch {
    return json(
      {
        ok: false,
        error: "boot_request_failed",
        message: "Impossible d'enregistrer la demande d'arrêt",
      },
      503
    );
  }
}
