/** Décision pure : démarrer les services ou non selon la réponse Worker. */

/**
 * @param {import('./worker-client.mjs').BootPeekResponse | null} peek
 * @param {{ consumed: boolean } | null} consumeResult
 */
export function shouldStartChatbotServices(peek, consumeResult) {
  if (!peek?.pending) {
    return {
      start: false,
      reason: peek?.status === "expired" ? "expired" : "no_pending_request",
    };
  }
  if (!consumeResult?.consumed) {
    return { start: false, reason: "consume_failed" };
  }
  return { start: true, reason: "worker_boot_request" };
}

/**
 * @param {Record<string, unknown>} health
 */
export function isNextJsProductionReady(health) {
  if (!health || typeof health !== "object") return false;
  const checks = health.checks;
  if (!checks || typeof checks !== "object") return false;
  const sqliteOk = checks.sqlite?.status === "ok";
  const lmOk = checks.lmStudio?.status === "connected";
  const modelReady =
    checks.model?.phase === "ready" && checks.model?.loaded === true;
  return sqliteOk && lmOk && modelReady;
}

/**
 * @param {{ status?: string, resultCount?: number }} searxngHealth
 */
export function isSearxngReady(searxngHealth) {
  return (
    searxngHealth?.status === "connected" &&
    (searxngHealth.resultCount ?? 0) > 0
  );
}

export function isDockerReady(dockerInfoExitCode) {
  return dockerInfoExitCode === 0;
}

/**
 * @param {number} lmModelsStatus
 */
export function isLmStudioApiReady(lmModelsStatus) {
  return lmModelsStatus === 200;
}

/**
 * Backoff delay with cap.
 * @param {number} attempt 0-based
 * @param {number} baseMs
 * @param {number} maxMs
 */
export function retryDelayMs(attempt, baseMs = 2000, maxMs = 30_000) {
  return Math.min(baseMs * 2 ** attempt, maxMs);
}
