import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import {
  authenticateAccessOnly,
  isAppSessionBearerHeader,
  isAuthRequired,
  isHealthCheckPath,
  isInternalHealthAuthorized,
} from "@/lib/auth/request-auth-edge";
import { apiErrorBody } from "@/lib/http/api-error";

export async function middleware(request: NextRequest) {
  const forwardWithUserId = (userId: string) => {
    const requestHeaders = new Headers(request.headers);
    requestHeaders.set("x-user-id", userId);
    return NextResponse.next({
      request: { headers: requestHeaders },
    });
  };

  if (!isAuthRequired()) {
    return forwardWithUserId("local");
  }

  if (isHealthCheckPath(request.nextUrl.pathname)) {
    if (isInternalHealthAuthorized(request)) {
      return forwardWithUserId("health-check");
    }
  }

  // Bearer app : laisser le runtime Node valider (sqlite) — ne pas bloquer à l'Edge
  if (isAppSessionBearerHeader(request)) {
    return NextResponse.next();
  }

  const auth = await authenticateAccessOnly(request);
  if (!auth.authenticated) {
    const accept = request.headers.get("accept") ?? "";
    if (accept.includes("text/html")) {
      const html = `<!DOCTYPE html><html lang="fr"><head><meta charset="utf-8"/><meta name="viewport" content="width=device-width, initial-scale=1"/><title>Session</title><style>body{font-family:system-ui,sans-serif;background:#18181a;color:#e4e4e7;display:grid;place-items:center;min-height:100dvh;margin:0;padding:1.5rem;text-align:center}a{color:#a5b4fc}</style></head><body><div><h1>Session expirée</h1><p>Authentification Cloudflare Access requise.</p><p><a href="/">Réessayer</a></p></div></body></html>`;
      return new NextResponse(html, {
        status: 401,
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    }
    return NextResponse.json(
      apiErrorBody(
        "AUTH_REQUIRED",
        "Non autorisé — authentification Cloudflare Access requise"
      ),
      {
        status: 401,
        headers: { "Content-Type": "application/json" },
      }
    );
  }

  return forwardWithUserId(auth.userId ?? "local");
}

export const config = {
  matcher: [
    "/api/:path*",
    "/chat/:path*",
    "/mail/:path*",
    "/files/:path*",
    "/settings/:path*",
    "/",
  ],
};
