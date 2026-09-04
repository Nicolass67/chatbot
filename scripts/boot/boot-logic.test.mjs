import { describe, expect, it } from "vitest";
import {
  isDockerReady,
  isLmStudioApiReady,
  isNextJsProductionReady,
  isSearxngReady,
  retryDelayMs,
  shouldStartChatbotServices,
} from "./boot-logic.mjs";

describe("shouldStartChatbotServices", () => {
  it("manual boot — no pending request", () => {
    expect(shouldStartChatbotServices({ pending: false }, null)).toEqual({
      start: false,
      reason: "no_pending_request",
    });
  });

  it("expired request — no services", () => {
    expect(
      shouldStartChatbotServices({ pending: false, status: "expired" }, null)
    ).toEqual({
      start: false,
      reason: "expired",
    });
  });

  it("valid pending + consume ok — start allowed", () => {
    expect(
      shouldStartChatbotServices(
        { pending: true, requestId: "abc" },
        { consumed: true }
      )
    ).toEqual({
      start: true,
      reason: "worker_boot_request",
    });
  });

  it("already consumed — no start", () => {
    expect(
      shouldStartChatbotServices(
        { pending: true, requestId: "abc" },
        { consumed: false }
      )
    ).toEqual({
      start: false,
      reason: "consume_failed",
    });
  });
});

describe("readiness helpers", () => {
  it("docker ready", () => {
    expect(isDockerReady(0)).toBe(true);
    expect(isDockerReady(1)).toBe(false);
  });

  it("searxng ready", () => {
    expect(isSearxngReady({ status: "connected", resultCount: 2 })).toBe(true);
    expect(isSearxngReady({ status: "connected", resultCount: 0 })).toBe(false);
  });

  it("lm studio api ready", () => {
    expect(isLmStudioApiReady(200)).toBe(true);
    expect(isLmStudioApiReady(503)).toBe(false);
  });

  it("next.js production ready", () => {
    const health = {
      checks: {
        sqlite: { status: "ok" },
        lmStudio: { status: "connected" },
        model: { phase: "ready", loaded: true },
      },
    };
    expect(isNextJsProductionReady(health)).toBe(true);
    expect(
      isNextJsProductionReady({
        checks: { ...health.checks, model: { phase: "loading", loaded: false } },
      })
    ).toBe(false);
  });

  it("retry backoff capped", () => {
    expect(retryDelayMs(0)).toBe(2000);
    expect(retryDelayMs(10)).toBeLessThanOrEqual(30_000);
  });
});
