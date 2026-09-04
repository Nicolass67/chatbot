import { backendOfflineProxyResponse } from "./backend";

interface ProxyEnv {
  PRIVATE_API: Fetcher;
}

const ORIGIN = "http://127.0.0.1:3000";

const HOP_BY_HOP = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "proxy-connection",
  "te",
  "trailers",
  "transfer-encoding",
  "upgrade",
]);

/** Headers Cloudflare edge — ne pas transmettre tels quels à l'origin. */
const STRIP_REQUEST = new Set([
  ...HOP_BY_HOP,
  "host",
  "cf-connecting-ip",
  "cf-ipcountry",
  "cf-ray",
  "cf-visitor",
  "cf-worker",
  "cf-ew-via",
  "cdn-loop",
]);

export function buildUpstreamHeaders(request: Request): Headers {
  const headers = new Headers();
  for (const [key, value] of request.headers) {
    if (STRIP_REQUEST.has(key.toLowerCase())) continue;
    headers.append(key, value);
  }

  headers.set("host", "127.0.0.1:3000");

  const clientUrl = new URL(request.url);
  headers.set("x-forwarded-host", clientUrl.host);
  headers.set("x-forwarded-proto", clientUrl.protocol.replace(":", ""));
  const clientIp = request.headers.get("cf-connecting-ip");
  if (clientIp) {
    headers.set("x-forwarded-for", clientIp);
  }

  return headers;
}

export function filterResponseHeaders(
  headers: Headers,
  clientOrigin: string
): Headers {
  const out = new Headers();
  for (const [key, value] of headers) {
    const lower = key.toLowerCase();
    if (HOP_BY_HOP.has(lower)) continue;

    if (lower === "location") {
      out.set(key, rewriteLocation(value, clientOrigin));
      continue;
    }

    out.append(key, value);
  }
  return out;
}

export function rewriteLocation(location: string, clientOrigin: string): string {
  if (location.startsWith("/")) return location;
  try {
    const parsed = new URL(location);
    if (
      parsed.hostname === "127.0.0.1" ||
      parsed.hostname === "localhost"
    ) {
      return `${clientOrigin}${parsed.pathname}${parsed.search}${parsed.hash}`;
    }
  } catch {
    /* keep original */
  }
  return location;
}

export function methodAllowsBody(method: string): boolean {
  return !["GET", "HEAD"].includes(method.toUpperCase());
}

export async function proxyToOrigin(
  request: Request,
  env: ProxyEnv,
  pathname: string,
  search: string
): Promise<Response> {
  const upstreamUrl = `${ORIGIN}${pathname}${search}`;

  try {
    const init: RequestInit = {
      method: request.method,
      headers: buildUpstreamHeaders(request),
      redirect: "manual",
    };

    if (methodAllowsBody(request.method)) {
      init.body = request.body;
    }

    const upstream = await env.PRIVATE_API.fetch(upstreamUrl, init);

    if (upstream.status >= 502) {
      await upstream.arrayBuffer().catch(() => undefined);
      return backendOfflineProxyResponse(request);
    }

    const clientOrigin = new URL(request.url).origin;

    let responseHeaders: Headers;
    try {
      responseHeaders = filterResponseHeaders(upstream.headers, clientOrigin);
    } catch {
      return backendOfflineProxyResponse(request);
    }

    return new Response(upstream.body ?? null, {
      status: upstream.status,
      statusText: upstream.statusText,
      headers: responseHeaders,
    });
  } catch {
    return backendOfflineProxyResponse(request);
  }
}
