import { describe, expect, it, vi } from "vitest";
import { handleStartServices } from "./start-services";

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
  BOOT_KV: createMemoryKv(),
};

function startServicesRequest(headers: Record<string, string> = {}): Request {
  return new Request("https://chatbot.example.workers.dev/start-services", {
    method: "POST",
    headers: {
      "Cf-Access-Jwt-Assertion": "jwt-test",
      ...headers,
    },
  });
}

describe("handleStartServices", () => {
  it("returns 401 without Cloudflare Access JWT", async () => {
    const request = new Request(
      "https://chatbot.example.workers.dev/start-services",
      { method: "POST" }
    );
    const response = await handleStartServices(request, baseEnv);
    expect(response.status).toBe(401);
    const body = (await response.json()) as { error: string };
    expect(body.error).toBe("access_required");
  });

  it("creates a boot request without WoL", async () => {
    const response = await handleStartServices(startServicesRequest(), baseEnv);
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      ok: boolean;
      message: string;
      bootRequestId?: string;
      bootRequestExpiresAt?: string;
    };
    expect(body.ok).toBe(true);
    expect(body.message).toContain("démarrage");
    expect(body.bootRequestId).toBeTruthy();
    expect(body.bootRequestExpiresAt).toBeTruthy();
  });
});
