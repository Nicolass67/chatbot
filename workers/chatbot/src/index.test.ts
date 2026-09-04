import { describe, expect, it, vi, afterEach } from "vitest";
import worker from "./index";

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

describe("worker routing when backend offline", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("GET /status never throws and reports backend offline", async () => {
    const env = {
      PRIVATE_API: {
        fetch: async () => {
          throw new Error("tunnel_down");
        },
      } as unknown as Fetcher,
      FREEBOX_APP_ID: "fr.chatbot.woltest.20250901b",
      FREEBOX_API_DOMAIN: "example.freeboxos.fr",
      FREEBOX_HTTPS_PORT: "443",
      FREEBOX_WOL_MAC: "00:00:00:00:00:00",
      FREEBOX_APP_TOKEN: "secret",
      BOOT_KV: createMemoryKv(),
    };

    const response = await worker.fetch(
      new Request("https://chatbot.example.workers.dev/status"),
      env
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({
      worker: "ok",
      backend: "offline",
    });
  });

  it("GET / returns offline page instead of throwing", async () => {
    const env = {
      PRIVATE_API: {
        fetch: async () => {
          throw new Error("tunnel_down");
        },
      } as unknown as Fetcher,
      FREEBOX_APP_ID: "fr.chatbot.woltest.20250901b",
      FREEBOX_API_DOMAIN: "example.freeboxos.fr",
      FREEBOX_HTTPS_PORT: "443",
      FREEBOX_WOL_MAC: "00:00:00:00:00:00",
      FREEBOX_APP_TOKEN: "secret",
      BOOT_KV: createMemoryKv(),
    };

    const response = await worker.fetch(
      new Request("https://chatbot.example.workers.dev/", {
        headers: { Accept: "text/html" },
      }),
      env
    );
    expect(response.status).toBe(503);
    const html = await response.text();
    expect(html).toContain("Réveiller ou relancer");
    expect(html).toContain("Relancer les services");
  });

  it("POST /wake does not call PRIVATE_API", async () => {
    const vpcFetch = vi.fn(async () => {
      throw new Error("tunnel_down");
    });

    vi.stubGlobal(
      "fetch",
      vi.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.endsWith("/api/v4/login/")) {
          return new Response(
            JSON.stringify({
              success: true,
              result: { challenge: "abc" },
            })
          );
        }
        if (url.endsWith("/api/v4/login/session/")) {
          return new Response(
            JSON.stringify({
              success: true,
              result: { session_token: "sess", permissions: ["settings"] },
            })
          );
        }
        if (url.endsWith("/api/v4/lan/wol/pub/")) {
          return new Response(JSON.stringify({ success: true, result: null }));
        }
        throw new Error(`unexpected ${url}`);
      })
    );

    const env = {
      PRIVATE_API: { fetch: vpcFetch } as unknown as Fetcher,
      FREEBOX_APP_ID: "fr.chatbot.woltest.20250901b",
      FREEBOX_API_DOMAIN: "example.freeboxos.fr",
      FREEBOX_HTTPS_PORT: "443",
      FREEBOX_WOL_MAC: "00:00:00:00:00:00",
      FREEBOX_APP_TOKEN: "secret",
      BOOT_KV: createMemoryKv(),
    };

    const response = await worker.fetch(
      new Request("https://chatbot.example.workers.dev/wake", {
        method: "POST",
        headers: { "Cf-Access-Jwt-Assertion": "jwt-test" },
      }),
      env
    );

    expect(response.status).toBe(200);
    expect(vpcFetch).not.toHaveBeenCalled();
  });

  it("POST /start-services creates boot request without WoL", async () => {
    const vpcFetch = vi.fn(async () => {
      throw new Error("tunnel_down");
    });

    const env = {
      PRIVATE_API: { fetch: vpcFetch } as unknown as Fetcher,
      FREEBOX_APP_ID: "fr.chatbot.woltest.20250901b",
      FREEBOX_API_DOMAIN: "example.freeboxos.fr",
      FREEBOX_HTTPS_PORT: "443",
      FREEBOX_WOL_MAC: "00:00:00:00:00:00",
      FREEBOX_APP_TOKEN: "secret",
      BOOT_KV: createMemoryKv(),
    };

    const response = await worker.fetch(
      new Request("https://chatbot.example.workers.dev/start-services", {
        method: "POST",
        headers: { "Cf-Access-Jwt-Assertion": "jwt-test" },
      }),
      env
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      ok: boolean;
      bootRequestId?: string;
    };
    expect(body.ok).toBe(true);
    expect(body.bootRequestId).toBeTruthy();
    expect(vpcFetch).not.toHaveBeenCalled();
  });

  it("POST /shutdown-pc creates shutdown boot request", async () => {
    const vpcFetch = vi.fn(async () => {
      throw new Error("tunnel_down");
    });

    const env = {
      PRIVATE_API: { fetch: vpcFetch } as unknown as Fetcher,
      FREEBOX_APP_ID: "fr.chatbot.woltest.20250901b",
      FREEBOX_API_DOMAIN: "example.freeboxos.fr",
      FREEBOX_HTTPS_PORT: "443",
      FREEBOX_WOL_MAC: "00:00:00:00:00:00",
      FREEBOX_APP_TOKEN: "secret",
      BOOT_KV: createMemoryKv(),
    };

    const response = await worker.fetch(
      new Request("https://chatbot.example.workers.dev/shutdown-pc", {
        method: "POST",
        headers: { "Cf-Access-Jwt-Assertion": "jwt-test" },
      }),
      env
    );

    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      ok: boolean;
      action?: string;
      bootRequestId?: string;
    };
    expect(body.ok).toBe(true);
    expect(body.action).toBe("shutdown");
    expect(body.bootRequestId).toBeTruthy();
    expect(vpcFetch).not.toHaveBeenCalled();
  });
});
