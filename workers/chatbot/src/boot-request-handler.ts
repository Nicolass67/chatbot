import {
  consumeBootRequest,
  peekBootRequest,
} from "./boot-request";
import {
  machineAuthFailureResponse,
  verifyBootMachineToken,
} from "./machine-auth";

export interface BootRequestEnv {
  BOOT_KV: KVNamespace;
  BOOT_MACHINE_TOKEN?: string;
}

function json(data: unknown, status = 200): Response {
  return Response.json(data, { status });
}

export async function handleBootRequestGet(
  request: Request,
  env: BootRequestEnv
): Promise<Response> {
  if (!verifyBootMachineToken(request, env.BOOT_MACHINE_TOKEN)) {
    return machineAuthFailureResponse();
  }

  const peek = await peekBootRequest(env.BOOT_KV);
  return json(peek);
}

export async function handleBootRequestConsume(
  request: Request,
  env: BootRequestEnv
): Promise<Response> {
  if (!verifyBootMachineToken(request, env.BOOT_MACHINE_TOKEN)) {
    return machineAuthFailureResponse();
  }

  let requestId: string | undefined;
  if (request.headers.get("content-type")?.includes("application/json")) {
    try {
      const body = (await request.json()) as { requestId?: string };
      requestId = body.requestId?.trim() || undefined;
    } catch {
      return json({ ok: false, error: "invalid_json" }, 400);
    }
  }

  const result = await consumeBootRequest(env.BOOT_KV, requestId);
  return json({
    ok: result.consumed,
    consumed: result.consumed,
    pending: result.peek.pending,
    status: result.peek.status,
    requestId: result.peek.requestId,
  });
}
