/**
 * Cloudflare Access JWT verification (Edge-compatible — Web Crypto only).
 * Validates Cf-Access-Jwt-Assertion when CF_ACCESS_ENABLED=true.
 *
 * Uses JWKS (`keys`) from /cdn-cgi/access/certs — not X.509 PEM as SPKI
 * (public_certs are certificate objects; importing them as SPKI always fails).
 */

export interface CloudflareAccessConfig {
  enabled: boolean;
  teamDomain: string | undefined;
  aud: string | undefined;
}

export interface CloudflareAccessAuthResult {
  authenticated: boolean;
  userId?: string;
  email?: string;
}

interface JwtHeader {
  alg: string;
  kid?: string;
}

interface JwtPayload {
  aud?: string | string[];
  email?: string;
  exp?: number;
  iss?: string;
  sub?: string;
}

interface JwkRsa {
  kid?: string;
  kty: string;
  alg?: string;
  use?: string;
  n?: string;
  e?: string;
}

type JwksCache = {
  keys: JwkRsa[];
  fetchedAt: number;
};

const CERT_CACHE_TTL_MS = 60 * 60 * 1000;
let jwksCache: JwksCache | null = null;

export function getCloudflareAccessConfig(): CloudflareAccessConfig {
  return {
    enabled: process.env.CF_ACCESS_ENABLED === "true",
    teamDomain: process.env.CF_ACCESS_TEAM_DOMAIN?.trim() || undefined,
    aud: process.env.CF_ACCESS_AUD?.trim() || undefined,
  };
}

export function isCloudflareAccessConfigured(): boolean {
  const cfg = getCloudflareAccessConfig();
  return cfg.enabled && !!cfg.teamDomain && !!cfg.aud;
}

function decodeBase64UrlToBytes(input: string): Uint8Array {
  const padded = input.replace(/-/g, "+").replace(/_/g, "/");
  const padLen = (4 - (padded.length % 4)) % 4;
  const base64 = padded + "=".repeat(padLen);
  if (typeof atob === "function") {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
  }
  return Uint8Array.from(Buffer.from(base64, "base64"));
}

function decodeBase64UrlToString(input: string): string {
  const bytes = decodeBase64UrlToBytes(input);
  return new TextDecoder().decode(bytes);
}

function parseJwt(token: string): {
  header: JwtHeader;
  payload: JwtPayload;
  signingInput: string;
  signature: Uint8Array;
} {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new Error("JWT invalide");
  }
  const [headerB64, payloadB64, signatureB64] = parts;
  const header = JSON.parse(decodeBase64UrlToString(headerB64)) as JwtHeader;
  const payload = JSON.parse(decodeBase64UrlToString(payloadB64)) as JwtPayload;
  const signature = decodeBase64UrlToBytes(signatureB64);
  return {
    header,
    payload,
    signingInput: `${headerB64}.${payloadB64}`,
    signature,
  };
}

async function fetchCloudflareJwks(teamDomain: string): Promise<JwkRsa[]> {
  const now = Date.now();
  if (jwksCache && now - jwksCache.fetchedAt < CERT_CACHE_TTL_MS) {
    return jwksCache.keys;
  }

  const res = await fetch(`https://${teamDomain}/cdn-cgi/access/certs`, {
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) {
    throw new Error(
      `Impossible de récupérer les certificats Cloudflare Access (${res.status})`
    );
  }

  const data = (await res.json()) as { keys?: JwkRsa[] };
  const keys = (data.keys ?? []).filter(
    (k) => k.kty === "RSA" && typeof k.n === "string" && typeof k.e === "string"
  );

  if (keys.length === 0) {
    throw new Error("Aucun JWK Cloudflare Access disponible");
  }

  jwksCache = { keys, fetchedAt: now };
  return keys;
}

function signatureToArrayBuffer(signature: Uint8Array): ArrayBuffer {
  return signature.buffer.slice(
    signature.byteOffset,
    signature.byteOffset + signature.byteLength
  ) as ArrayBuffer;
}

async function verifyWithJwk(
  signingInput: string,
  signature: Uint8Array,
  jwk: JwkRsa
): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "jwk",
    {
      kty: "RSA",
      n: jwk.n,
      e: jwk.e,
      alg: "RS256",
      ext: true,
    },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );

  return crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    signatureToArrayBuffer(signature),
    new TextEncoder().encode(signingInput)
  );
}

function validatePayload(
  payload: JwtPayload,
  teamDomain: string,
  aud: string
): void {
  const now = Math.floor(Date.now() / 1000);
  if (payload.exp !== undefined && payload.exp < now) {
    throw new Error("JWT expiré");
  }

  const audiences = Array.isArray(payload.aud)
    ? payload.aud
    : payload.aud
      ? [payload.aud]
      : [];
  if (!audiences.includes(aud)) {
    throw new Error("Audience JWT invalide");
  }

  const expectedIss = `https://${teamDomain}`;
  if (payload.iss && payload.iss !== expectedIss) {
    throw new Error("Issuer JWT invalide");
  }
}

export async function verifyCloudflareAccessJwt(
  token: string,
  teamDomain: string,
  aud: string
): Promise<CloudflareAccessAuthResult> {
  const { header, payload, signingInput, signature } = parseJwt(token);

  if (header.alg !== "RS256") {
    throw new Error(`Algorithme JWT non supporté: ${header.alg}`);
  }

  validatePayload(payload, teamDomain, aud);

  const keys = await fetchCloudflareJwks(teamDomain);
  const ordered = header.kid
    ? [
        ...keys.filter((k) => k.kid === header.kid),
        ...keys.filter((k) => k.kid !== header.kid),
      ]
    : keys;

  let verified = false;
  for (const jwk of ordered) {
    try {
      if (await verifyWithJwk(signingInput, signature, jwk)) {
        verified = true;
        break;
      }
    } catch {
      // try next key
    }
  }

  if (!verified) {
    throw new Error("Signature JWT invalide");
  }

  return {
    authenticated: true,
    userId: payload.sub,
    email: payload.email,
  };
}

export async function authenticateCloudflareAccess(
  jwtAssertion: string | null
): Promise<CloudflareAccessAuthResult> {
  if (!isCloudflareAccessConfigured()) {
    return { authenticated: true, userId: "local" };
  }

  if (!jwtAssertion) {
    return { authenticated: false };
  }

  const cfg = getCloudflareAccessConfig();
  try {
    return await verifyCloudflareAccessJwt(
      jwtAssertion,
      cfg.teamDomain!,
      cfg.aud!
    );
  } catch {
    // Signature / aud / issuer invalides → refuser sans planter le middleware (500).
    return { authenticated: false };
  }
}

/** Reset JWKS cache — tests only */
export function resetCloudflareAccessCertCache(): void {
  jwksCache = null;
}
