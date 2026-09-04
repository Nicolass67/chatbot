import { afterEach, describe, expect, it, vi } from "vitest";
import { apiFetch, ApiAuthError, ApiNetworkError } from "./api-fetch";

describe("apiFetch", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("returns response when ok", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("ok", { status: 200 }))
    );
    const res = await apiFetch("/api/x");
    expect(res.status).toBe(200);
  });

  it("dispatches auth event and throws on 401", async () => {
    const dispatch = vi.fn();
    vi.stubGlobal("window", { dispatchEvent: dispatch });
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => new Response("no", { status: 401 }))
    );
    await expect(apiFetch("/api/x")).rejects.toBeInstanceOf(ApiAuthError);
    expect(dispatch).toHaveBeenCalled();
  });

  it("dispatches network event and throws on fetch failure", async () => {
    const dispatch = vi.fn();
    vi.stubGlobal("window", { dispatchEvent: dispatch });
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => {
        throw new TypeError("Failed to fetch");
      })
    );
    await expect(apiFetch("/api/x")).rejects.toBeInstanceOf(ApiNetworkError);
    expect(dispatch).toHaveBeenCalled();
  });
});
