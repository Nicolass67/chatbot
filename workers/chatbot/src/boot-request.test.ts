import { describe, expect, it, vi, beforeEach } from "vitest";
import {
  consumeBootRequest,
  createBootRequest,
  peekBootRequest,
  bootRequestTtlSeconds,
} from "./boot-request";

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

describe("bootRequestTtlSeconds", () => {
  it("defaults to 300 seconds", () => {
    expect(bootRequestTtlSeconds({})).toBe(300);
  });

  it("accepts valid override", () => {
    expect(bootRequestTtlSeconds({ BOOT_REQUEST_TTL_SECONDS: "120" })).toBe(
      120
    );
  });
});

describe("createBootRequest + peek + consume", () => {
  let kv: KVNamespace;

  beforeEach(() => {
    kv = createMemoryKv();
  });

  it("creates a pending shutdown request", async () => {
    const record = await createBootRequest(kv, 300, "shutdown");
    expect(record.action).toBe("shutdown");
    const peek = await peekBootRequest(kv);
    expect(peek.action).toBe("shutdown");
  });

  it("creates a pending request without secrets", async () => {
    const record = await createBootRequest(kv, 300, "restart");
    expect(record.requestId).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    );
    expect(record.status).toBe("pending");
    expect(record.action).toBe("restart");
    expect(JSON.stringify(record)).not.toContain("token");
  });

  it("returns pending on peek with action", async () => {
    const created = await createBootRequest(kv, 300, "restart");
    const peek = await peekBootRequest(kv);
    expect(peek.pending).toBe(true);
    expect(peek.requestId).toBe(created.requestId);
    expect(peek.action).toBe("restart");
  });

  it("consumes once then pending false", async () => {
    const created = await createBootRequest(kv, 300);
    const first = await consumeBootRequest(kv, created.requestId);
    expect(first.consumed).toBe(true);
    expect(first.peek.pending).toBe(false);

    const second = await consumeBootRequest(kv, created.requestId);
    expect(second.consumed).toBe(false);
    expect(second.peek.pending).toBe(false);
  });

  it("rejects consume with wrong requestId", async () => {
    await createBootRequest(kv, 300);
    const result = await consumeBootRequest(kv, "wrong-id");
    expect(result.consumed).toBe(false);
    const peek = await peekBootRequest(kv);
    expect(peek.pending).toBe(true);
  });

  it("returns no pending when absent", async () => {
    const peek = await peekBootRequest(kv);
    expect(peek.pending).toBe(false);
  });

  it("treats expired pending as not pending", async () => {
    const expired: Awaited<ReturnType<typeof createBootRequest>> = {
      requestId: "expired-id",
      createdAt: new Date(Date.now() - 600_000).toISOString(),
      expiresAt: new Date(Date.now() - 60_000).toISOString(),
      status: "pending",
      action: "start",
    };
    await kv.put("boot:current", JSON.stringify(expired));
    const peek = await peekBootRequest(kv);
    expect(peek.pending).toBe(false);
    expect(peek.status).toBe("expired");
  });
});
