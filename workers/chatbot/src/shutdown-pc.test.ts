import { describe, expect, it, vi } from "vitest";
import { handleShutdownPc } from "./shutdown-pc";

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

function shutdownPcRequest(headers: Record<string, string> = {}): Request {
  return new Request("https://chatbot.example.workers.dev/shutdown-pc", {
    method: "POST",
    headers: {
      "Cf-Access-Jwt-Assertion": "jwt-test",
      ...headers,
    },
  });
}

describe("handleShutdownPc", () => {
  it("returns 401 without Cloudflare Access JWT", async () => {
    const request = new Request(
      "https://chatbot.example.workers.dev/shutdown-pc",
      { method: "POST" }
    );
    const response = await handleShutdownPc(request, baseEnv);
    expect(response.status).toBe(401);
  });

  it("creates a shutdown boot request", async () => {
    const response = await handleShutdownPc(shutdownPcRequest(), baseEnv);
    expect(response.status).toBe(200);
    const body = (await response.json()) as {
      ok: boolean;
      action: string;
      bootRequestId?: string;
    };
    expect(body.ok).toBe(true);
    expect(body.action).toBe("shutdown");
    expect(body.bootRequestId).toBeTruthy();
  });
});
