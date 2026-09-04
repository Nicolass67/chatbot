import { describe, expect, it, vi } from "vitest";
import { formatWakeTestResult, postWakeTest } from "./test-wake-client";

describe("postWakeTest", () => {
  it("POSTs /wake and parses JSON response", async () => {
    const fetchFn = vi.fn(async () => {
      return new Response(
        JSON.stringify({ ok: true, message: "Wake-on-LAN envoyé à la Freebox" }),
        { status: 200 }
      );
    });

    const result = await postWakeTest(fetchFn);
    expect(fetchFn).toHaveBeenCalledWith("/wake", { method: "POST" });
    expect(result.status).toBe(200);
    expect(result.body).toEqual({
      ok: true,
      message: "Wake-on-LAN envoyé à la Freebox",
    });
  });

  it("returns raw text when response is not JSON", async () => {
    const fetchFn = vi.fn(async () => {
      return new Response("bad gateway", { status: 502 });
    });

    const result = await postWakeTest(fetchFn);
    expect(result.status).toBe(502);
    expect(result.body).toBe("bad gateway");
  });
});

describe("formatWakeTestResult", () => {
  it("formats status and JSON without secrets", () => {
    const formatted = formatWakeTestResult({
      status: 502,
      body: {
        ok: false,
        step: "wol",
        error_code: "insufficient_rights",
      },
    });
    expect(formatted).toContain("HTTP 502");
    expect(formatted).toContain('"step": "wol"');
  });
});
