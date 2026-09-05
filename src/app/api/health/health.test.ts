import { describe, expect, it } from "vitest";
import {
  decideHealthHttpStatus,
  decideHealthStatusLabel,
} from "@/lib/health/decide-health-status";

describe("decideHealthHttpStatus", () => {
  it("returns 200 when sqlite is ok (even if LM down)", () => {
    expect(decideHealthHttpStatus({ sqliteOk: true })).toBe(200);
  });

  it("returns 503 only when sqlite fails", () => {
    expect(decideHealthHttpStatus({ sqliteOk: false })).toBe(503);
  });
});

describe("decideHealthStatusLabel", () => {
  it("ok when sqlite + lm connected", () => {
    expect(
      decideHealthStatusLabel({ sqliteOk: true, lmStudioConnected: true })
    ).toBe("ok");
  });

  it("degraded when sqlite ok but lm down", () => {
    expect(
      decideHealthStatusLabel({ sqliteOk: true, lmStudioConnected: false })
    ).toBe("degraded");
  });

  it("error when sqlite fails", () => {
    expect(
      decideHealthStatusLabel({ sqliteOk: false, lmStudioConnected: true })
    ).toBe("error");
  });
});
