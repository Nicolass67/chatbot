/**
 * Pure health probes used by Supervisor and tests (injectable fetch).
 */

export type ProbeResult = {
  ok: boolean;
  process: "running" | "stopped" | "unknown";
  health: "healthy" | "unhealthy" | "unknown";
  readiness: "ready" | "not_ready" | "loading" | "unknown";
  detail?: Record<string, unknown>;
  error?: string;
};

export type FetchLike = (
  url: string,
  init?: { signal?: AbortSignal; headers?: Record<string, string> }
) => Promise<{ ok: boolean; status: number; json?: () => Promise<unknown>; text?: () => Promise<string> }>;

async function withTimeout<T>(
  ms: number,
  fn: (signal: AbortSignal) => Promise<T>
): Promise<T> {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try {
    return await fn(ctrl.signal);
  } finally {
    clearTimeout(t);
  }
}

export async function probeNextHealth(
  baseUrl: string,
  fetchImpl: FetchLike = fetch as FetchLike,
  timeoutMs = 5000
): Promise<ProbeResult> {
  try {
    const res = await withTimeout(timeoutMs, (signal) =>
      fetchImpl(`${baseUrl.replace(/\/$/, "")}/api/health`, { signal })
    );
    if (!res.ok && res.status !== 200) {
      // degraded (200 with degraded) vs down
      if (res.status >= 500) {
        return {
          ok: false,
          process: "running",
          health: "unhealthy",
          readiness: "not_ready",
          detail: { status: res.status },
        };
      }
    }
    let body: Record<string, unknown> = {};
    try {
      body = (await res.json?.()) as Record<string, unknown>;
    } catch {
      body = {};
    }
    const ready = body.ready === true || body.status === "ok" || body.status === "degraded";
    const aiReady = body.aiReady === true;
    return {
      ok: res.ok || res.status === 200,
      process: "running",
      health: ready || res.status === 200 ? "healthy" : "unhealthy",
      readiness: aiReady ? "ready" : "not_ready",
      detail: body,
    };
  } catch (e) {
    return {
      ok: false,
      process: "stopped",
      health: "unhealthy",
      readiness: "not_ready",
      error: e instanceof Error ? e.message : String(e),
    };
  }
}

export async function probeSearxng(
  baseUrl = "http://127.0.0.1:8080",
  fetchImpl: FetchLike = fetch as FetchLike,
  timeoutMs = 8000
): Promise<ProbeResult> {
  try {
    const res = await withTimeout(timeoutMs, (signal) =>
      fetchImpl(`${baseUrl.replace(/\/$/, "")}/`, { signal })
    );
    const ok = res.ok || res.status === 200 || res.status === 301 || res.status === 302;
    return {
      ok,
      process: ok ? "running" : "unknown",
      health: ok ? "healthy" : "unhealthy",
      readiness: ok ? "ready" : "not_ready",
      detail: { status: res.status },
    };
  } catch (e) {
    return {
      ok: false,
      process: "stopped",
      health: "unhealthy",
      readiness: "not_ready",
      error: e instanceof Error ? e.message : String(e),
    };
  }
}

export async function probeLmStudio(
  baseUrl = "http://127.0.0.1:1234",
  fetchImpl: FetchLike = fetch as FetchLike,
  timeoutMs = 8000
): Promise<ProbeResult> {
  try {
    const res = await withTimeout(timeoutMs, (signal) =>
      fetchImpl(`${baseUrl.replace(/\/$/, "")}/v1/models`, { signal })
    );
    if (!res.ok) {
      return {
        ok: false,
        process: "running",
        health: "unhealthy",
        readiness: "not_ready",
        detail: { status: res.status },
      };
    }
    const body = (await res.json?.()) as { data?: Array<{ id?: string }> };
    const models = body?.data ?? [];
    const hasModel = models.length > 0;
    return {
      ok: true,
      process: "running",
      health: "healthy",
      readiness: hasModel ? "ready" : "not_ready",
      detail: { modelCount: models.length, models: models.map((m) => m.id) },
    };
  } catch (e) {
    return {
      ok: false,
      process: "stopped",
      health: "unhealthy",
      readiness: "not_ready",
      error: e instanceof Error ? e.message : String(e),
    };
  }
}

/** cloudflared: process presence is OS-level; HTTP reachability of public URL is optional. */
export async function probeLocalPort(
  url: string,
  fetchImpl: FetchLike = fetch as FetchLike,
  timeoutMs = 5000
): Promise<ProbeResult> {
  try {
    const res = await withTimeout(timeoutMs, (signal) => fetchImpl(url, { signal }));
    const ok = res.status > 0;
    return {
      ok,
      process: "running",
      health: res.ok || res.status < 500 ? "healthy" : "unhealthy",
      readiness: res.ok || res.status < 500 ? "ready" : "not_ready",
      detail: { status: res.status },
    };
  } catch (e) {
    return {
      ok: false,
      process: "unknown",
      health: "unhealthy",
      readiness: "not_ready",
      error: e instanceof Error ? e.message : String(e),
    };
  }
}
