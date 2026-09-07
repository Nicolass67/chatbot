/** Requête déjà authentifiée par Cloudflare Access (JWT injecté en edge). */
export function hasCloudflareAccessJwt(request: Request): boolean {
  const jwt = request.headers.get("Cf-Access-Jwt-Assertion");
  return typeof jwt === "string" && jwt.length > 0;
}

/**
 * Auth edge pour actions power (wake / start / shutdown) depuis l’app native.
 *
 * - Navigateur / offline-page : cookie Access → `Cf-Access-Jwt-Assertion`
 * - iOS (Bypass `/api/*`) : Bearer session app `chs_…` (obtenu derrière Access)
 *
 * Ne valide pas le token en SQLite (PC peut être éteint) — la possession d’un
 * Bearer `chs_` implique un login Access antérieur (ADR 001).
 */
export function hasEdgeUserAuth(request: Request): boolean {
  if (hasCloudflareAccessJwt(request)) return true;
  const auth = request.headers.get("Authorization") ?? "";
  const m = /^Bearer\s+(chs_[A-Za-z0-9_-]+)\s*$/i.exec(auth);
  return Boolean(m?.[1] && m[1].length >= 12);
}
