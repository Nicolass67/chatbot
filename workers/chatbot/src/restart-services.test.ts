import { describe, expect, it, vi } from "vitest";
import { handleRestartServices } from "./restart-services";

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

function restartServicesRequest(headers: Record<string, string> = {}): Request {
  return new Request("https://chatbot.example.workers.dev/restart-services", {
    method: "POST",
    headers: {
      "Cf-Access-Jwt-Assertion": "jwt-test",
      ...headers,
    },
  });
}

describe("handleRestartServices", () => {
  it("returns 401 without Cloudflare Access JWT", async () => {
    const request = new Request(
      "https://chatbot.example.workers.dev/restart-services",
      { method: "POST" }
    );
    const response = await handleRestartServices(request, baseEnv);
    expect(response.status).toBe(401);
  });

  it("creates a restart boot request", async () => {
    const response = await handleRestartServices(restartServicesRequest(), baseEnv);
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      ok: boolean;
      action: string;
      bootRequestId?: string;
    };
    expect(body.ok).toBe(true);
    expect(body.action).toBe("restart");
    expect(body.bootRequestId).toBeTruthy();
  });
});
