import {
  authenticateAccessOnly,
  isAppSessionBearerHeader,
  isAuthRequired,
  isCloudflareAccessConfigured,
  isHealthCheckPath,
  isInternalHealthAuthorized,
  getHealthCheckToken,
} from "./request-auth-edge";
import {
  extractBearerToken,
  looksLikeAppSessionToken,
  resolveAppSessionToken,
} from "./app-session";
import type { AuthResult } from "./types";

export {
  getHealthCheckToken,
  isAuthRequired,
  isCloudflareAccessConfigured,
  isHealthCheckPath,
  isInternalHealthAuthorized,
  isAppSessionBearerHeader,
};

/**
 * Auth complète Node : Access JWT **ou** session app Bearer (`chs_`).
 */
export async function authenticateRequest(request: Request): Promise<AuthResult> {
  const bearer = extractBearerToken(request);
  if (bearer && looksLikeAppSessionToken(bearer)) {
    const session = await resolveAppSessionToken(bearer);
    if (session) {
      return { authenticated: true, userId: session.userId };
    }
    return { authenticated: false };
  }

  return authenticateAccessOnly(request);
}
