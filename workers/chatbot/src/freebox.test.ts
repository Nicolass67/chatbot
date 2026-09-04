import { createHmac } from "node:crypto";
import { describe, expect, it, vi } from "vitest";
import {
  computeHmacPassword,
  diagnosticResponseBody,
  freeboxOpenSession,
  freeboxWakeOnLan,
  freeboxWakePc,
  FreeboxStepError,
  isFreeboxTlsTrustFailure,
} from "./freebox";

const config = {
  apiDomain: "example.freeboxos.fr",
  httpsPort: "443",
  appId: "fr.chatbot.woltest.20250901b",
  appToken: "test-app-token-secret",
  wolMac: "00:00:00:00:00:00",
};

describe("computeHmacPassword", () => {
  it("produces HMAC-SHA1 hex matching Node reference", async () => {
    const challenge = "test-challenge-value";
    const expected = createHmac("sha1", config.appToken)
      .update(challenge)
      .digest("hex");

    const password = await computeHmacPassword(challenge, config.appToken);
    expect(password).toBe(expected);
    expect(password).toMatch(/^[a-f0-9]{40}$/);
  });

  it("uses app_token as HMAC key and challenge as message", async () => {
    const challenge = "fixed-challenge-12345";
    const appToken = "fixed-app-token-key";

    const expected = createHmac("sha1", appToken).update(challenge).digest("hex");
    const reversed = createHmac("sha1", challenge).update(appToken).digest("hex");

    expect(await computeHmacPassword(challenge, appToken)).toBe(expected);
    expect(expected).not.toBe(reversed);
  });
});

describe("diagnosticResponseBody", () => {
  it("never includes token-like fields", () => {
    const body = diagnosticResponseBody({
      step: "session",
      status: 403,
      error_code: "invalid_token",
      msg: "Invalid application token",
      permissions: ["settings", "calls"],
      uid: "fbx-uid-123",
    });
    expect(body).toEqual({
      ok: false,
      step: "session",
      status: 403,
      error_code: "invalid_token",
      msg: "Invalid application token",
      permissions: ["settings", "calls"],
      uid: "fbx-uid-123",
    });
    expect(JSON.stringify(body)).not.toContain("session-token-xyz");
    expect(JSON.stringify(body)).not.toContain("test-app-token");
  });
});

describe("isFreeboxTlsTrustFailure", () => {
  it("detects Cloudflare 526 TLS trust failures", () => {
    const response = new Response("error code: 526", { status: 526 });
    expect(isFreeboxTlsTrustFailure(response, "error code: 526")).toBe(true);
  });
});

describe("freeboxOpenSession", () => {
  it("surfaces TLS trust failures instead of invalid_response", async () => {
    const fetchFn = vi.fn(async () =>
      new Response("error code: 526", {
        status: 526,
        headers: { "content-type": "text/plain; charset=UTF-8" },
      })
    );

    try {
      await freeboxOpenSession(fetchFn, config);
      expect.unreachable("should throw");
    } catch (error) {
      expect(error).toBeInstanceOf(FreeboxStepError);
      const stepError = error as FreeboxStepError;
      expect(stepError.diagnostic.error_code).toBe("tls_trust_failed");
      expect(stepError.diagnostic.step).toBe("challenge");
      expect(stepError.diagnostic.msg).toContain("freeboxos.fr");
    }
  });

  it("opens a session with challenge HMAC flow", async () => {
    const fetchFn = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.endsWith("/api/v4/login/")) {
        return new Response(
          JSON.stringify({
            success: true,
            result: { challenge: "challenge-abc", uid: "fbx-uid-1" },
          })
        );
      }
      if (url.endsWith("/api/v4/login/session/")) {
        const body = JSON.parse(String(init?.body)) as {
          app_id: string;
          password: string;
        };
        expect(body.app_id).toBe(config.appId);
        const expectedPassword = createHmac("sha1", config.appToken)
          .update("challenge-abc")
          .digest("hex");
        expect(body.password).toBe(expectedPassword);
        return new Response(
          JSON.stringify({
            success: true,
            result: {
              session_token: "session-token-xyz",
              permissions: ["settings"],
            },
          })
        );
      }
      throw new Error(`unexpected fetch: ${url}`);
    });

    const session = await freeboxOpenSession(fetchFn, config);
    expect(session.sessionToken).toBe("session-token-xyz");
    expect(session.permissions).toEqual(["settings"]);
    expect(session.uid).toBe("fbx-uid-1");
    expect(fetchFn).toHaveBeenCalledTimes(2);
  });

  it("throws challenge step diagnostic on login failure", async () => {
    const fetchFn = vi.fn(async () => {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "internal_error",
          msg: "login unavailable",
        }),
        { status: 503 }
      );
    });

    try {
      await freeboxOpenSession(fetchFn, config);
      expect.unreachable("should throw");
    } catch (error) {
      expect(error).toBeInstanceOf(FreeboxStepError);
      const stepError = error as FreeboxStepError;
      expect(stepError.diagnostic).toEqual({
        step: "challenge",
        status: 503,
        error_code: "internal_error",
        msg: "login unavailable",
      });
    }
  });

  it("throws session step diagnostic on authentication failure", async () => {
    const fetchFn = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.endsWith("/api/v4/login/")) {
        return new Response(
          JSON.stringify({
            success: true,
            result: { challenge: "challenge-abc", uid: "fbx-uid-1" },
          })
        );
      }
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "invalid_token",
          msg: "Invalid application token",
        }),
        { status: 403 }
      );
    });

    try {
      await freeboxOpenSession(fetchFn, config);
      expect.unreachable("should throw");
    } catch (error) {
      expect(error).toBeInstanceOf(FreeboxStepError);
      const stepError = error as FreeboxStepError;
      expect(stepError.diagnostic.step).toBe("session");
      expect(stepError.diagnostic.status).toBe(403);
      expect(stepError.diagnostic.error_code).toBe("invalid_token");
      expect(stepError.diagnostic.uid).toBe("fbx-uid-1");
    }
  });
});

describe("freeboxWakeOnLan", () => {
  it("posts WoL with configured MAC only", async () => {
    const fetchFn = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      expect(url).toContain("/api/v4/lan/wol/pub/");
      expect(init?.method).toBe("POST");
      expect(init?.headers).toMatchObject({
        "X-Fbx-App-Auth": "session-token-xyz",
      });
      const body = JSON.parse(String(init?.body)) as {
        mac: string;
        password: string;
      };
      expect(body).toEqual({ mac: config.wolMac, password: "" });
      return new Response(JSON.stringify({ success: true, result: null }));
    });

    await freeboxWakeOnLan(fetchFn, config, "session-token-xyz");
    expect(fetchFn).toHaveBeenCalledOnce();
  });

  it("throws wol step diagnostic with permissions", async () => {
    const fetchFn = vi.fn(async () => {
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "insufficient_rights",
          msg: "Application token not granted",
        }),
        { status: 403 }
      );
    });

    try {
      await freeboxWakeOnLan(fetchFn, config, "session-token-xyz", {
        permissions: ["calls"],
        uid: "fbx-uid-1",
      });
      expect.unreachable("should throw");
    } catch (error) {
      expect(error).toBeInstanceOf(FreeboxStepError);
      const stepError = error as FreeboxStepError;
      expect(stepError.diagnostic).toEqual({
        step: "wol",
        status: 403,
        error_code: "insufficient_rights",
        msg: "Application token not granted",
        permissions: ["calls"],
        uid: "fbx-uid-1",
      });
    }
  });
});

describe("freeboxWakePc", () => {
  it("runs login session then WoL", async () => {
    const fetchFn = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.endsWith("/api/v4/login/")) {
        return new Response(
          JSON.stringify({
            success: true,
            result: { challenge: "challenge-abc" },
          })
        );
      }
      if (url.endsWith("/api/v4/login/session/")) {
        return new Response(
          JSON.stringify({
            success: true,
            result: { session_token: "session-token-xyz", permissions: ["settings"] },
          })
        );
      }
      if (url.endsWith("/api/v4/lan/wol/pub/")) {
        return new Response(JSON.stringify({ success: true, result: null }));
      }
      throw new Error(`unexpected fetch: ${url}`);
    });

    await freeboxWakePc(fetchFn, config);
    expect(fetchFn).toHaveBeenCalledTimes(3);
  });
});
