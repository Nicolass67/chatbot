import { describe, expect, it } from "vitest";
import {
  FAILURE_CONTRACTS,
  contractFor,
  isOptionalAtStartup,
} from "./failure-modes";
import {
  decideHealthHttpStatus,
  decideHealthStatusLabel,
} from "@/lib/health/decide-health-status";

describe("failure contracts", () => {
  it("lists unique ids", () => {
    const ids = FAILURE_CONTRACTS.map((c) => c.id);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("marks AI/search optional at startup", () => {
    expect(isOptionalAtStartup("lm_unavailable")).toBe(true);
    expect(isOptionalAtStartup("searxng_down")).toBe(true);
    expect(isOptionalAtStartup("sqlite_down")).toBe(false);
  });

  it("infrastructure modes use infra_repair or wake_pc", () => {
    expect(contractFor("nextjs_down").expectedRecovery).toBe("infra_repair");
    expect(contractFor("docker_down").expectedRecovery).toBe("infra_repair");
    expect(contractFor("pc_offline").expectedRecovery).toBe("wake_pc");
    expect(contractFor("crash_loop").expectedRecovery).toBe("degrade");
  });

  it("abort/cancel must cancel_clean", () => {
    expect(contractFor("stream_abort").expectedRecovery).toBe("cancel_clean");
  });

  it("stale + double submit must ignore_stale", () => {
    expect(contractFor("stale_response").expectedRecovery).toBe("ignore_stale");
    expect(contractFor("double_submit").expectedRecovery).toBe("ignore_stale");
  });
});

describe("health vs optional AI (failure injection matrix)", () => {
  it("scenario: LM down → process alive (200 degraded)", () => {
    expect(decideHealthHttpStatus({ sqliteOk: true })).toBe(200);
    expect(
      decideHealthStatusLabel({
        sqliteOk: true,
        lmStudioConnected: false,
      })
    ).toBe("degraded");
  });

  it("scenario: SQLite down → not ready (503)", () => {
    expect(decideHealthHttpStatus({ sqliteOk: false })).toBe(503);
    expect(
      decideHealthStatusLabel({
        sqliteOk: false,
        lmStudioConnected: true,
      })
    ).toBe("error");
  });

  it("scenario: all core ok → ok", () => {
    expect(
      decideHealthStatusLabel({
        sqliteOk: true,
        lmStudioConnected: true,
      })
    ).toBe("ok");
  });
});
