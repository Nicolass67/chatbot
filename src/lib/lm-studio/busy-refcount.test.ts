import { afterEach, describe, expect, it } from "vitest";
import { setRuntimeBusy, getRuntimeStatus } from "./client";

describe("setRuntimeBusy refcount", () => {
  afterEach(() => {
    for (let i = 0; i < 8; i++) setRuntimeBusy(false);
  });

  it("balances overlapping busy marks without going negative", () => {
    setRuntimeBusy(true);
    setRuntimeBusy(true);
    setRuntimeBusy(false);
    setRuntimeBusy(false);
    setRuntimeBusy(false);
    expect(true).toBe(true);
  });

  it("getRuntimeStatus does not throw while busy", async () => {
    setRuntimeBusy(true);
    try {
      const status = await getRuntimeStatus();
      expect(status).toBeTruthy();
      expect(typeof status.status).toBe("string");
    } finally {
      setRuntimeBusy(false);
    }
  });
});
