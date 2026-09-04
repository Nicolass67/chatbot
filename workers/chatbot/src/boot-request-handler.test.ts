import { describe, expect, it, vi } from "vitest";
import {
  handleBootRequestConsume,
  handleBootRequestGet,
} from "./boot-request-handler";

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

const token = "machine-token-test";

describe("boot-request handlers", () => {
  it("GET returns 401 without machine token", async () => {
    const response = await handleBootRequestGet(
      new Request("https://example.com/boot-request"),
      { BOOT_KV: createMemoryKv(), BOOT_MACHINE_TOKEN: token }
    );
    expect(response.status).toBe(401);
  });

  it("GET returns pending false when empty", async () => {
    const response = await handleBootRequestGet(
      new Request("https://example.com/boot-request", {
        headers: { Authorization: `Bearer ${token}` },
      }),
      { BOOT_KV: createMemoryKv(), BOOT_MACHINE_TOKEN: token }
    );
    expect(response.status).toBe(200);
    await expect(response.json()).resolves.toEqual({ pending: false });
  });

  it("POST consume returns pending false after consumption", async () => {
    const kv = createMemoryKv();
    const record = {
      requestId: "req-1",
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 300_000).toISOString(),
      status: "pending" as const,
    };
    await kv.put("boot:current", JSON.stringify(record));

    const getRes = await handleBootRequestGet(
      new Request("https://example.com/boot-request", {
        headers: { Authorization: `Bearer ${token}` },
      }),
      { BOOT_KV: kv, BOOT_MACHINE_TOKEN: token }
    );
    await expect(getRes.json()).resolves.toMatchObject({
      pending: true,
      requestId: "req-1",
    });

    const consumeRes = await handleBootRequestConsume(
      new Request("https://example.com/boot-request", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ requestId: "req-1" }),
      }),
      { BOOT_KV: kv, BOOT_MACHINE_TOKEN: token }
    );
    await expect(consumeRes.json()).resolves.toMatchObject({
      ok: true,
      consumed: true,
      pending: false,
    });

    const afterRes = await handleBootRequestGet(
      new Request("https://example.com/boot-request", {
        headers: { Authorization: `Bearer ${token}` },
      }),
      { BOOT_KV: kv, BOOT_MACHINE_TOKEN: token }
    );
    await expect(afterRes.json()).resolves.toMatchObject({
      pending: false,
      status: "consumed",
    });
  });
});
