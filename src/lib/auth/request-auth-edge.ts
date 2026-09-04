/**
 * Auth Edge-compatible (Web Crypto only) — utilisé par middleware.
 * Les sessions app Bearer sont validées côté Node (apiAuthGuard).
 */
import {
  authenticateCloudflareAccess,
  isCloudflareAccessConfigured,
} from "./cloudflare-access";
import type { AuthResult } from "./types";

const JWT_HEADER = "cf-access-jwt-assertion";

export function getHealthCheckToken(): string | undefined {
  return process.env.HEALTH_CHECK_TOKEN?.trim() || undefined;
}

export function isHealthCheckPath(pathname: string): boolean {
  return pathname === "/api/health";
}

export function isAppSessionBearerHeader(request: Request): boolean {
  const auth = request.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) return false;
  return auth.slice("Bearer ".length).trim().startsWith("chs_");
}

export function isInternalHealthAuthorized(request: Request): boolean {
  const token = getHealthCheckToken();
  if (!token) return false;

  const auth = request.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) return false;
  const bearer = auth.slice("Bearer ".length).trim();
  if (bearer.startsWith("chs_")) return false;
  return bearer === token;
}

export async function authenticateAccessOnly(
  request: Request
): Promise<AuthResult> {
  const url = new URL(request.url);

  if (isHealthCheckPath(url.pathname) && isInternalHealthAuthorized(request)) {
    return { authenticated: true, userId: "health-check" };
  }

  // Ne pas valider chs_ ici (Edge) — laisser passer jusqu'au runtime Node
  if (isAppSessionBearerHeader(request)) {
    return { authenticated: false };
  }

  const jwt = request.headers.get(JWT_HEADER);
  const result = await authenticateCloudflareAccess(jwt);

  return {
    authenticated: result.authenticated,
    userId: result.userId ?? result.email,
  };
}

export function isAuthRequired(): boolean {
  return isCloudflareAccessConfigured();
}

export { isCloudflareAccessConfigured };
