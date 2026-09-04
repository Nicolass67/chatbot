import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  authenticateCloudflareAccess,
  getCloudflareAccessConfig,
  resetCloudflareAccessCertCache,
  verifyCloudflareAccessJwt,
} from "./cloudflare-access";

function b64url(data: ArrayBuffer | Uint8Array | string): string {
  const bytes =
    typeof data === "string"
      ? new TextEncoder().encode(data)
      : data instanceof Uint8Array
        ? data
        : new Uint8Array(data);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function mintTestJwt(aud: string, teamDomain: string) {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"]
  );
  const jwk = (await crypto.subtle.exportKey(
    "jwk",
    pair.publicKey
  )) as JsonWebKey & { kid?: string; alg?: string; use?: string };
  jwk.kid = "test-kid";
  jwk.alg = "RS256";
  jwk.use = "sig";

  const header = b64url(
    JSON.stringify({ alg: "RS256", kid: "test-kid", typ: "JWT" })
  );
  const now = Math.floor(Date.now() / 1000);
  const payload = b64url(
    JSON.stringify({
      aud: [aud],
      email: "user@example.com",
      exp: now + 3600,
      iss: `https://${teamDomain}`,
      sub: "user-1",
    })
  );
  const signingInput = `${header}.${payload}`;
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    pair.privateKey,
    new TextEncoder().encode(signingInput)
  );
  const token = `${signingInput}.${b64url(signature)}`;
  return { token, jwk };
}

describe("cloudflare-access", () => {
  const originalEnv = { ...process.env };

  beforeEach(() => {
    process.env = { ...originalEnv };
    resetCloudflareAccessCertCache();
    vi.unstubAllGlobals();
  });

  it("autorise en pass-through quand CF Access est désactivé", async () => {
    process.env.CF_ACCESS_ENABLED = "false";
    const result = await authenticateCloudflareAccess(null);
    expect(result.authenticated).toBe(true);
    expect(result.userId).toBe("local");
  });

  it("refuse sans JWT quand CF Access est activé", async () => {
    process.env.CF_ACCESS_ENABLED = "true";
    process.env.CF_ACCESS_TEAM_DOMAIN = "team.cloudflareaccess.com";
    process.env.CF_ACCESS_AUD = "test-aud";
    const result = await authenticateCloudflareAccess(null);
    expect(result.authenticated).toBe(false);
  });

  it("lit la configuration depuis les variables d'environnement", () => {
    process.env.CF_ACCESS_ENABLED = "true";
    process.env.CF_ACCESS_TEAM_DOMAIN = "team.cloudflareaccess.com";
    process.env.CF_ACCESS_AUD = "abc123";
    expect(getCloudflareAccessConfig()).toEqual({
      enabled: true,
      teamDomain: "team.cloudflareaccess.com",
      aud: "abc123",
    });
  });

  it("vérifie un JWT Access via JWKS (pas PEM/SPKI)", async () => {
    const team = "team.cloudflareaccess.com";
    const aud = "app-aud";
    const { token, jwk } = await mintTestJwt(aud, team);

    vi.stubGlobal(
      "fetch",
      vi.fn(async () =>
        Response.json({
          keys: [jwk],
          public_certs: [
            {
              kid: "test-kid",
              cert: "-----BEGIN CERTIFICATE-----\nNOT_A_KEY\n-----END CERTIFICATE-----",
            },
          ],
        })
      )
    );

    const result = await verifyCloudflareAccessJwt(token, team, aud);
    expect(result.authenticated).toBe(true);
    expect(result.email).toBe("user@example.com");
    expect(result.userId).toBe("user-1");
  });

  it("authenticateCloudflareAccess ne propage pas les erreurs JWT", async () => {
    process.env.CF_ACCESS_ENABLED = "true";
    process.env.CF_ACCESS_TEAM_DOMAIN = "team.cloudflareaccess.com";
    process.env.CF_ACCESS_AUD = "test-aud";
    const result = await authenticateCloudflareAccess("not.a.jwt");
    expect(result.authenticated).toBe(false);
  });
});
