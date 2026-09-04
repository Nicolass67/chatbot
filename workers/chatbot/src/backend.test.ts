import { describe, expect, it } from "vitest";
import {
  backendOfflineProxyResponse,
  checkBackendState,
  wantsJson,
} from "./backend";

describe("checkBackendState", () => {
  it("returns online when health responds 200", async () => {
    const env = {
      PRIVATE_API: {
        fetch: async () => new Response(JSON.stringify({ ok: true }), { status: 200 }),
      } as unknown as Fetcher,
    };
    expect(await checkBackendState(env)).toBe("online");
  });

  it("returns online when health is degraded but Next.js responds", async () => {
    const env = {
      PRIVATE_API: {
        fetch: async () =>
          new Response(
            JSON.stringify({
              status: "degraded",
              checks: { nextjs: { status: "ok" }, lmStudio: { status: "unavailable" } },
            }),
            { status: 503, headers: { "Content-Type": "application/json" } }
          ),
      } as unknown as Fetcher,
    };
    expect(await checkBackendState(env)).toBe("online");
  });

  it("returns offline when health responds non-200", async () => {
    const env = {
      PRIVATE_API: {
        fetch: async () => new Response("bad gateway", { status: 502 }),
      } as unknown as Fetcher,
    };
    expect(await checkBackendState(env)).toBe("offline");
  });

  it("sends Bearer HEALTH_CHECK_TOKEN when configured", async () => {
    let auth: string | null = null;
    const env = {
      HEALTH_CHECK_TOKEN: "test-health-token",
      PRIVATE_API: {
        fetch: async (_input: RequestInfo | URL, init?: RequestInit) => {
          auth = new Headers(init?.headers).get("authorization");
          return new Response(JSON.stringify({ status: "ok" }), { status: 200 });
        },
      } as unknown as Fetcher,
    };
    expect(await checkBackendState(env)).toBe("online");
    expect(auth).toBe("Bearer test-health-token");
  });
});

describe("backendOfflineProxyResponse", () => {
  it("returns JSON 503 for API requests", async () => {
    const request = new Request("https://chatbot.example/api/health", {
      headers: { Accept: "application/json" },
    });
    const response = backendOfflineProxyResponse(request);
    expect(response.status).toBe(503);
    const body = (await response.json()) as { error: string };
    expect(body.error).toBe("backend_offline");
  });

  it("returns HTML 503 for browser navigation", async () => {
    const request = new Request("https://chatbot.example/chat/new", {
      headers: { Accept: "text/html" },
    });
    const response = backendOfflineProxyResponse(request);
    expect(response.status).toBe(503);
    expect(response.headers.get("content-type")).toContain("text/html");
    const html = await response.text();
    expect(html).toContain("Réveiller ou relancer");
    expect(html).toContain("Relancer les services");
    expect(html).toContain("Allumer le PC");
  });
});

describe("wantsJson", () => {
  it("detects API paths", () => {
    const request = new Request("https://chatbot.example/api/settings");
    expect(wantsJson(request)).toBe(true);
  });
});
