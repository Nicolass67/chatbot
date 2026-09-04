import { authenticateRequest } from "./request-auth";
import type { AuthGuard, AuthResult } from "./types";

const USER_ID_HEADER = "x-user-id";

export function getRequestUserId(request: Request): string {
  return request.headers.get(USER_ID_HEADER)?.trim() || "local";
}

/**
 * Guard API : header middleware (Access) **ou** auth complète (Bearer app / Access).
 * Pour Bearer `chs_`, le middleware n'injecte pas x-user-id — on résout ici (Node).
 */
export const apiAuthGuard: AuthGuard = {
  async authenticate(request: Request): Promise<AuthResult> {
    const authHeader = request.headers.get("authorization");
    if (authHeader?.startsWith("Bearer chs_")) {
      return authenticateRequest(request);
    }
    const headerUserId = request.headers.get(USER_ID_HEADER)?.trim();
    if (headerUserId) {
      return { authenticated: true, userId: headerUserId };
    }
    return authenticateRequest(request);
  },
};

export async function requireApiAuth(request: Request): Promise<AuthResult> {
  const auth = await apiAuthGuard.authenticate(request);
  if (!auth.authenticated || !auth.userId) {
    throw new Error("Non autorisé");
  }
  return auth;
}

export { USER_ID_HEADER };
