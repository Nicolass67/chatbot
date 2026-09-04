import { checkBackendState } from "./backend";
import type { BackendEnv } from "./backend";

export async function handleStatus(
  env: BackendEnv,
  fetchFn?: typeof fetch
): Promise<Response> {
  const backend = await checkBackendState(env, fetchFn);

  return Response.json(
    {
      worker: "ok",
      backend,
    },
    {
      status: 200,
      headers: { "Cache-Control": "no-store" },
    }
  );
}
