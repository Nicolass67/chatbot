/** Requête déjà authentifiée par Cloudflare Access (JWT injecté en edge). */
export function hasCloudflareAccessJwt(request: Request): boolean {
  const jwt = request.headers.get("Cf-Access-Jwt-Assertion");
  return typeof jwt === "string" && jwt.length > 0;
}
