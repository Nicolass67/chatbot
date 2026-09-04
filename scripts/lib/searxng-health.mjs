/**
 * Health check SearXNG pour scripts CLI (miroir de searxng-health.ts).
 */

function buildSearxngHealthCheckUrl(baseUrl) {
  const url = new URL(`${baseUrl.replace(/\/$/, "")}/search`);
  url.searchParams.set("q", "test");
  url.searchParams.set("format", "json");
  url.searchParams.set("engines", "wikipedia");
  return url;
}

export async function checkSearxngHealth(baseUrl, timeoutMs = 8000) {
  const checkedAt = new Date().toISOString();
  const root = baseUrl.replace(/\/$/, "");
  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const url = buildSearxngHealthCheckUrl(root);

    const response = await fetch(url.toString(), {
      method: "GET",
      headers: { Accept: "application/json" },
      signal: controller.signal,
    });

    if (response.status >= 502 && response.status <= 504) {
      return {
        status: "starting",
        url: root,
        message: `SearXNG HTTP ${response.status} — démarrage en cours`,
        checkedAt,
        httpStatus: response.status,
      };
    }

    if (!response.ok) {
      return {
        status: "unavailable",
        url: root,
        message: `SearXNG HTTP ${response.status}`,
        checkedAt,
        httpStatus: response.status,
      };
    }

    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.includes("application/json")) {
      return {
        status: "unavailable",
        url: root,
        message: "SearXNG n'a pas renvoyé de JSON",
        checkedAt,
        httpStatus: response.status,
      };
    }

    const data = await response.json();
    if (!Array.isArray(data.results)) {
      return {
        status: "unavailable",
        url: root,
        message: "Réponse SearXNG sans tableau results",
        checkedAt,
        httpStatus: response.status,
      };
    }

    if (data.results.length === 0) {
      const unresponsive = data.unresponsive_engines ?? [];
      if (unresponsive.length > 0) {
        return {
          status: "starting",
          url: root,
          message:
            "SearXNG répond mais les moteurs sont suspendus — réessayez dans quelques secondes",
          checkedAt,
          httpStatus: response.status,
          resultCount: 0,
        };
      }
      return {
        status: "starting",
        url: root,
        message: "SearXNG répond mais aucun résultat test",
        checkedAt,
        httpStatus: response.status,
        resultCount: 0,
      };
    }

    return {
      status: "connected",
      url: root,
      message: "SearXNG connecté",
      checkedAt,
      httpStatus: response.status,
      resultCount: data.results.length,
    };
  } catch (error) {
    const isAbort =
      error instanceof DOMException && error.name === "AbortError";
    return {
      status: "starting",
      url: root,
      message: isAbort
        ? "SearXNG ne répond pas encore (timeout) — démarrage ou moteurs lents"
        : error instanceof Error
          ? error.message
          : String(error),
      checkedAt,
    };
  } finally {
    clearTimeout(timeoutId);
  }
}

export async function waitForSearxngHealth(baseUrl, options = {}) {
  const timeoutMs = options.timeoutMs ?? 60_000;
  const intervalMs = options.intervalMs ?? 2000;
  const checkTimeoutMs = options.checkTimeoutMs ?? 3000;
  const onProgress = options.onProgress;
  const started = Date.now();

  let last = await checkSearxngHealth(baseUrl, checkTimeoutMs);
  if (last.status === "connected" && (last.resultCount ?? 0) > 0) return last;

  while (Date.now() - started < timeoutMs) {
    await new Promise((r) => setTimeout(r, intervalMs));
    last = await checkSearxngHealth(baseUrl, checkTimeoutMs);
    onProgress?.(Date.now() - started, last);
    if (last.status === "connected" && (last.resultCount ?? 0) > 0) return last;
  }

  return last;
}
