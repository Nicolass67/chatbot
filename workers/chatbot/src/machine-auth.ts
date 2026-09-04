/** Auth machine→Worker pour /boot-request (Bearer token, hors Access utilisateur). */

export function extractBearerToken(request: Request): string | null {
  const header = request.headers.get("Authorization");
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice("Bearer ".length).trim();
  return token.length > 0 ? token : null;
}

export function verifyBootMachineToken(
  request: Request,
  expectedToken: string | undefined
): boolean {
  if (!expectedToken?.trim()) return false;
  const provided = extractBearerToken(request);
  if (!provided) return false;
  return timingSafeEqual(provided, expectedToken.trim());
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

export function machineAuthFailureResponse(): Response {
  return Response.json(
    { ok: false, error: "machine_auth_required" },
    { status: 401 }
  );
}
