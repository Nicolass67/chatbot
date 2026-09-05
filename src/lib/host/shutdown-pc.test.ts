import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";

const spawnSync = vi.hoisted(() => vi.fn());

vi.mock("node:child_process", () => ({
  spawnSync,
}));

describe("scheduleHostPcShutdown", () => {
  const originalPlatform = process.platform;

  beforeEach(() => {
    spawnSync.mockReset();
  });

  afterEach(() => {
    Object.defineProperty(process, "platform", {
      value: originalPlatform,
      configurable: true,
    });
  });

  it("refuse hors Windows", async () => {
    Object.defineProperty(process, "platform", {
      value: "linux",
      configurable: true,
    });
    const { scheduleHostPcShutdown } = await import("./shutdown-pc");
    const result = scheduleHostPcShutdown();
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe("unsupported_platform");
    }
    expect(spawnSync).not.toHaveBeenCalled();
  });

  it("planifie shutdown /s /full sous Windows", async () => {
    Object.defineProperty(process, "platform", {
      value: "win32",
      configurable: true,
    });
    spawnSync.mockReturnValue({ status: 0, stdout: "", stderr: "" });
    const { scheduleHostPcShutdown } = await import("./shutdown-pc");
    const result = scheduleHostPcShutdown(60);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.delaySeconds).toBe(60);
    }
    expect(spawnSync).toHaveBeenCalledWith(
      "shutdown",
      expect.arrayContaining(["/s", "/full", "/t", "60"]),
      expect.any(Object)
    );
  });
});
