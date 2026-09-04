export interface FreeboxConfig {
  apiDomain: string;
  httpsPort: string;
  appId: string;
  appToken: string;
  wolMac: string;
}

export type FetchFn = typeof fetch;

export type FreeboxStep = "challenge" | "session" | "wol";

export interface FreeboxDiagnostic {
  step: FreeboxStep;
  status: number;
  error_code?: string;
  msg?: string;
  uid?: string;
  permissions?: string[];
}

interface FreeboxEnvelope<T> {
  success: boolean;
  result?: T;
  error_code?: string;
  msg?: string;
}

interface LoginChallengeResult {
  challenge: string;
  uid?: string;
}

interface SessionResult {
  session_token: string;
  permissions?: string[];
}

export class FreeboxStepError extends Error {
  readonly name = "FreeboxStepError";

  constructor(readonly diagnostic: FreeboxDiagnostic) {
    super(diagnostic.error_code ?? diagnostic.step);
  }
}

export function freeboxBaseUrl(
  config: Pick<FreeboxConfig, "apiDomain" | "httpsPort">
): string {
  return `https://${config.apiDomain}:${config.httpsPort}`;
}

/**
 * password = HMAC-SHA1(challenge, app_token) → hex
 * - clé HMAC : app_token
 * - message : challenge
 */
export async function computeHmacPassword(
  challenge: string,
  appToken: string
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(appToken),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(challenge)
  );
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function isFreeboxTlsTrustFailure(
  response: Response,
  raw: string
): boolean {
  const normalized = raw.trim().toLowerCase();
  return (
    response.status === 526 ||
    normalized === "error code: 526" ||
    normalized.includes("error code: 526")
  );
}

export const FREEBOX_TLS_TRUST_MESSAGE =
  "Le Worker Cloudflare ne peut pas valider le certificat TLS de la Freebox (domaine fbxos.fr signé par une CA privée Freebox). Configure un domaine xxx.freeboxos.fr avec Let's Encrypt dans Freebox OS, puis mets à jour FREEBOX_API_DOMAIN / FREEBOX_HTTPS_PORT sur le Worker.";

async function readFreeboxPayload<T>(
  response: Response,
  step: FreeboxStep
): Promise<FreeboxEnvelope<T>> {
  const contentType = response.headers.get("content-type") ?? "";
  const raw = await response.text();

  if (isFreeboxTlsTrustFailure(response, raw)) {
    throw new FreeboxStepError({
      step,
      status: response.status,
      error_code: "tls_trust_failed",
      msg: FREEBOX_TLS_TRUST_MESSAGE,
    });
  }

  try {
    return JSON.parse(raw) as FreeboxEnvelope<T>;
  } catch {
    const preview = raw.slice(0, 120).replace(/[\r\n]+/g, " ");
    throw new FreeboxStepError({
      step,
      status: response.status,
      error_code: "invalid_response",
      msg: `Réponse Freebox illisible (${contentType || "no content-type"}, ${raw.length} octets)`,
      uid: preview.startsWith("<!") ? "html_response" : undefined,
    });
  }
}

function stepError(
  step: FreeboxStep,
  response: Response,
  payload: FreeboxEnvelope<unknown>,
  extra: Partial<FreeboxDiagnostic> = {}
): FreeboxStepError {
  return new FreeboxStepError({
    step,
    status: response.status,
    error_code: payload.error_code,
    msg: payload.msg,
    ...extra,
  });
}

export interface FreeboxSessionInfo {
  sessionToken: string;
  permissions?: string[];
  uid?: string;
}

export async function freeboxOpenSession(
  fetchFn: FetchFn,
  config: FreeboxConfig
): Promise<FreeboxSessionInfo> {
  const base = freeboxBaseUrl(config);

  const loginResponse = await fetchFn(`${base}/api/v4/login/`, {
    method: "GET",
    headers: { Accept: "application/json" },
  });
  const loginPayload = await readFreeboxPayload<LoginChallengeResult>(
    loginResponse,
    "challenge"
  );

  if (!loginPayload.success || !loginPayload.result?.challenge) {
    throw stepError("challenge", loginResponse, loginPayload, {
      uid: loginPayload.result?.uid,
    });
  }

  const uid = loginPayload.result.uid;
  const password = await computeHmacPassword(
    loginPayload.result.challenge,
    config.appToken
  );

  const sessionResponse = await fetchFn(`${base}/api/v4/login/session/`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      app_id: config.appId,
      password,
    }),
  });

  const sessionPayload = await readFreeboxPayload<SessionResult>(
    sessionResponse,
    "session"
  );

  if (!sessionPayload.success || !sessionPayload.result?.session_token) {
    throw stepError("session", sessionResponse, sessionPayload, { uid });
  }

  return {
    sessionToken: sessionPayload.result.session_token,
    permissions: sessionPayload.result.permissions,
    uid,
  };
}

export async function freeboxWakeOnLan(
  fetchFn: FetchFn,
  config: FreeboxConfig,
  sessionToken: string,
  sessionInfo: Pick<FreeboxSessionInfo, "permissions" | "uid"> = {}
): Promise<void> {
  const base = freeboxBaseUrl(config);

  const response = await fetchFn(`${base}/api/v4/lan/wol/pub/`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Fbx-App-Auth": sessionToken,
    },
    body: JSON.stringify({
      mac: config.wolMac,
      password: "",
    }),
  });

  const payload = await readFreeboxPayload<unknown>(response, "wol");

  if (!payload.success) {
    throw stepError("wol", response, payload, {
      uid: sessionInfo.uid,
      permissions: sessionInfo.permissions,
    });
  }
}

export async function freeboxWakePc(
  fetchFn: FetchFn,
  config: FreeboxConfig
): Promise<FreeboxSessionInfo> {
  const session = await freeboxOpenSession(fetchFn, config);
  await freeboxWakeOnLan(fetchFn, config, session.sessionToken, session);
  return session;
}

export function diagnosticResponseBody(
  diagnostic: FreeboxDiagnostic
): Record<string, unknown> {
  const body: Record<string, unknown> = {
    ok: false,
    step: diagnostic.step,
    status: diagnostic.status,
  };

  if (diagnostic.error_code) body.error_code = diagnostic.error_code;
  if (diagnostic.msg) body.msg = diagnostic.msg;
  if (diagnostic.uid) body.uid = diagnostic.uid;
  if (diagnostic.permissions?.length) {
    body.permissions = diagnostic.permissions;
  }

  return body;
}
