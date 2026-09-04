/** Client HTTP vers GET/POST /boot-request sur le Worker. */

/**
 * @typedef {{ pending: boolean, requestId?: string, expiresAt?: string, status?: string }} BootPeekResponse
 * @typedef {{ cfAccessClientId?: string, cfAccessClientSecret?: string }} AccessServiceAuth
 */

/**
 * @param {string} token
 * @param {AccessServiceAuth} [accessAuth]
 */
function buildBootRequestHeaders(token, accessAuth) {
  /** @type {Record<string, string>} */
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/json",
  };
  if (accessAuth?.cfAccessClientId && accessAuth?.cfAccessClientSecret) {
    headers["CF-Access-Client-Id"] = accessAuth.cfAccessClientId;
    headers["CF-Access-Client-Secret"] = accessAuth.cfAccessClientSecret;
  }
  return headers;
}

/**
 * @param {Response} response
 */
async function parseBootJsonResponse(response) {
  if (response.status === 302 || response.status === 301) {
    const location = response.headers.get("location") ?? "";
    if (
      response.headers.get("www-authenticate")?.includes("Cloudflare-Access") ||
      location.includes("cloudflareaccess.com")
    ) {
      return { ok: false, error: "access_blocked", status: response.status };
    }
  }

  if (response.status === 401) {
    return { ok: false, error: "machine_auth_failed", status: 401 };
  }

  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) {
    const snippet = (await response.text()).slice(0, 120).toLowerCase();
    if (
      snippet.includes("<!doctype html") ||
      snippet.includes("cloudflareaccess.com") ||
      snippet.includes("cloudflare access")
    ) {
      return { ok: false, error: "access_blocked", status: response.status };
    }
    return {
      ok: false,
      error: "invalid_response",
      status: response.status,
    };
  }

  if (!response.ok) {
    return {
      ok: false,
      error: "worker_error",
      status: response.status,
    };
  }

  /** @type {BootPeekResponse} */
  const body = await response.json();
  return { ok: true, body };
}

/**
 * @param {string} baseUrl
 * @param {string} token
 * @param {typeof fetch} fetchFn
 * @param {AccessServiceAuth} [accessAuth]
 */
export async function peekBootRequest(
  baseUrl,
  token,
  fetchFn = fetch,
  accessAuth
) {
  const response = await fetchFn(`${baseUrl}/boot-request`, {
    method: "GET",
    headers: buildBootRequestHeaders(token, accessAuth),
    redirect: "manual",
  });

  return parseBootJsonResponse(response);
}

/**
 * @param {string} baseUrl
 * @param {string} token
 * @param {string | undefined} requestId
 * @param {typeof fetch} fetchFn
 * @param {AccessServiceAuth} [accessAuth]
 */
export async function consumeBootRequest(
  baseUrl,
  token,
  requestId,
  fetchFn = fetch,
  accessAuth
) {
  const response = await fetchFn(`${baseUrl}/boot-request`, {
    method: "POST",
    headers: {
      ...buildBootRequestHeaders(token, accessAuth),
      "Content-Type": "application/json",
    },
    body: JSON.stringify(requestId ? { requestId } : {}),
    redirect: "manual",
  });

  const parsed = await parseBootJsonResponse(response);
  if (!parsed.ok) {
    return {
      ok: false,
      error: parsed.error,
      consumed: false,
      status: parsed.status,
    };
  }

  const body = parsed.body;
  return {
    ok: body.ok === true,
    consumed: body.consumed === true,
    body,
  };
}

/**
 * @param {(attempt: number) => Promise<{ reachable: boolean, peek?: BootPeekResponse | null, error?: string, fatal?: boolean }>} fn
 * @param {{ timeoutMs?: number, baseDelayMs?: number, maxDelayMs?: number }} options
 */
export async function waitForWorkerBootPeek(fn, options = {}) {
  const timeoutMs = options.timeoutMs ?? 120_000;
  const baseDelayMs = options.baseDelayMs ?? 1500;
  const maxDelayMs = options.maxDelayMs ?? 10_000;
  const started = Date.now();
  let attempt = 0;

  while (Date.now() - started < timeoutMs) {
    const result = await fn(attempt);
    if (result.fatal) {
      return result;
    }
    if (result.reachable) {
      return result;
    }
    const delay = Math.min(baseDelayMs * 2 ** attempt, maxDelayMs);
    await new Promise((r) => setTimeout(r, delay));
    attempt += 1;
  }

  return { reachable: false, error: "worker_timeout" };
}
