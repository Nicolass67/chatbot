/** V2: Auth layer — Cloudflare Access JWT (see src/lib/auth/cloudflare-access.ts) */

export interface AuthResult {
  authenticated: boolean;
  userId?: string;
}

export interface AuthGuard {
  authenticate(request: Request): Promise<AuthResult>;
}

/** Local dev when CF_ACCESS_ENABLED=false */
export const noAuthGuard: AuthGuard = {
  async authenticate() {
    return { authenticated: true, userId: "local" };
  },
};

/**
 * V2: wrap route handlers with auth
 * export const POST = withAuth(async (req, auth) => { ... });
 */
export function withAuth<T extends unknown[]>(
  guard: AuthGuard,
  handler: (request: Request, auth: AuthResult, ...args: T) => Promise<Response>
) {
  return async (request: Request, ...args: T): Promise<Response> => {
    const auth = await guard.authenticate(request);
    if (!auth.authenticated) {
      return new Response(JSON.stringify({ error: "Non autorisé" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }
    return handler(request, auth, ...args);
  };
}
