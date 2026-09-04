import { describe, expect, it, vi } from "vitest";
import { handleWake } from "./wake";

function createMemoryKv(): KVNamespace {
  const store = new Map<string, string>();
  return {
    get: vi.fn(async (key: string) => store.get(key) ?? null),
    put: vi.fn(async (key: string, value: string) => {
      store.set(key, value);
    }),
    delete: vi.fn(async (key: string) => {
      store.delete(key);
    }),
    list: vi.fn(),
    getWithMetadata: vi.fn(),
  } as unknown as KVNamespace;
}

const baseEnv = {
  FREEBOX_APP_ID: "fr.chatbot.woltest.20250901b",
  FREEBOX_API_DOMAIN: "example.freeboxos.fr",
  FREEBOX_HTTPS_PORT: "443",
  FREEBOX_WOL_MAC: "00:00:00:00:00:00",
  FREEBOX_APP_TOKEN: "test-app-token-secret",
  BOOT_KV: createMemoryKv(),
};

function wakeRequest(headers: Record<string, string> = {}): Request {
  return new Request("https://chatbot.example.workers.dev/wake", {
    method: "POST",
    headers: {
      "Cf-Access-Jwt-Assertion": "jwt-test",
      ...headers,
    },
  });
}

describe("handleWake", () => {
  it("returns 401 without Cloudflare Access JWT", async () => {
    const request = new Request("https://chatbot.example.workers.dev/wake", {
      method: "POST",
    });
    const response = await handleWake(request, baseEnv, vi.fn());
    expect(response.status).toBe(401);
    const body = (await response.json()) as { error: string };
    expect(body.error).toBe("access_required");
  });

  it("returns 503 when FREEBOX_APP_TOKEN is missing", async () => {
    const response = await handleWake(
      wakeRequest(),
      { ...baseEnv, FREEBOX_APP_TOKEN: undefined },
      vi.fn()
    );
    expect(response.status).toBe(503);
    const body = (await response.json()) as { error: string };
    expect(body.error).toBe("configuration_missing");
  });

  it("returns success JSON on WoL flow", async () => {
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

    const response = await handleWake(wakeRequest(), baseEnv, fetchFn);
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      ok: boolean;
      message: string;
      bootRequestId?: string;
      bootRequestExpiresAt?: string;
    };
    expect(body.ok).toBe(true);
    expect(body.message).toContain("Wake-on-LAN");
    expect(body.bootRequestId).toBeTruthy();
    expect(body.bootRequestExpiresAt).toBeTruthy();
    expect(JSON.stringify(body)).not.toContain("session-token");
    expect(JSON.stringify(body)).not.toContain("test-app-token");
  });

  it("returns session diagnostic without leaking tokens", async () => {
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

    const response = await handleWake(wakeRequest(), baseEnv, fetchFn);
    expect(response.status).toBe(502);
    const body = (await response.json()) as {
      ok: boolean;
      step: string;
      status: number;
      error_code: string;
    };
    expect(body).toEqual({
      ok: false,
      step: "session",
      status: 403,
      error_code: "invalid_token",
      msg: "Invalid application token",
      uid: "fbx-uid-1",
    });
    expect(JSON.stringify(body)).not.toMatch(/session-token|test-app-token|password/i);
  });

  it("returns wol diagnostic with permissions", async () => {
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
            result: { session_token: "session-token-xyz", permissions: ["calls"] },
          })
        );
      }
      return new Response(
        JSON.stringify({
          success: false,
          error_code: "insufficient_rights",
          msg: "Application token not granted",
        }),
        { status: 403 }
      );
    });

    const response = await handleWake(wakeRequest(), baseEnv, fetchFn);
    expect(response.status).toBe(502);
    const body = (await response.json()) as {
      step: string;
      error_code: string;
      permissions: string[];
    };
    expect(body.step).toBe("wol");
    expect(body.error_code).toBe("insufficient_rights");
    expect(body.permissions).toEqual(["calls"]);
    expect(JSON.stringify(body)).not.toContain("session-token");
  });
});
