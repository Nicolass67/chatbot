/**
 * Liveness vs readiness for /api/health.
 * Process usable ⇔ SQLite OK. LM Studio down ⇒ degraded, not 503.
 */
export function decideHealthHttpStatus(params: {
  sqliteOk: boolean;
}): 200 | 503 {
  return params.sqliteOk ? 200 : 503;
}

export function decideHealthStatusLabel(params: {
  sqliteOk: boolean;
  lmStudioConnected: boolean;
}): "ok" | "degraded" | "error" {
  if (!params.sqliteOk) return "error";
  if (!params.lmStudioConnected) return "degraded";
  return "ok";
}
