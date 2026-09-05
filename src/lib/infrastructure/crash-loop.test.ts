import { describe, expect, it } from "vitest";
import { getServiceDefinition } from "./service-registry";
import {
  createCrashLoopState,
  noteSuccessfulRecovery,
  registerRestartAttempt,
} from "./crash-loop";

describe("crash-loop circuit breaker", () => {
  const def = getServiceDefinition("nextjs")!;

  it("allows restarts until maxRestarts within window", () => {
    let state = createCrashLoopState("nextjs");
    const t0 = 1_000_000;

    for (let i = 0; i < def.maxRestarts; i++) {
      // Jump past backoff between attempts
      const now = t0 + i * (def.maxBackoffMs + 1);
      const result = registerRestartAttempt(state, def, now);
      expect(result.allowed).toBe(true);
      state = result.state;
    }

    const blocked = registerRestartAttempt(
      state,
      def,
      t0 + def.maxRestarts * (def.maxBackoffMs + 1)
    );
    expect(blocked.allowed).toBe(false);
    expect(blocked.reason).toBe("max_restarts_exceeded");
    expect(blocked.state.circuitOpen).toBe(true);
  });

  it("enforces backoff between attempts", () => {
    let state = createCrashLoopState("nextjs");
    const t0 = 2_000_000;
    const first = registerRestartAttempt(state, def, t0);
    expect(first.allowed).toBe(true);
    state = first.state;

    const tooSoon = registerRestartAttempt(state, def, t0 + 100);
    expect(tooSoon.allowed).toBe(false);
    expect(tooSoon.reason).toBe("backoff");
  });

  it("clears circuit after openUntil and successful recovery resets", () => {
    let state = createCrashLoopState("nextjs");
    const t0 = 3_000_000;

    for (let i = 0; i < def.maxRestarts; i++) {
      const now = t0 + i * (def.maxBackoffMs + 1);
      state = registerRestartAttempt(state, def, now).state;
    }
    const open = registerRestartAttempt(
      state,
      def,
      t0 + def.maxRestarts * (def.maxBackoffMs + 1)
    );
    expect(open.state.circuitOpen).toBe(true);
    state = open.state;

    const afterCooldown = registerRestartAttempt(
      state,
      def,
      (state.openUntil ?? 0) + 1
    );
    expect(afterCooldown.allowed).toBe(true);
    expect(afterCooldown.state.circuitOpen).toBe(false);

    const recovered = noteSuccessfulRecovery(afterCooldown.state);
    expect(recovered.restarts).toEqual([]);
    expect(recovered.circuitOpen).toBe(false);
  });

  it("rejects while circuit still open", () => {
    let state = createCrashLoopState("docker");
    const docker = getServiceDefinition("docker")!;
    const t0 = 4_000_000;
    for (let i = 0; i < docker.maxRestarts; i++) {
      state = registerRestartAttempt(
        state,
        docker,
        t0 + i * (docker.maxBackoffMs + 1)
      ).state;
    }
    state = registerRestartAttempt(
      state,
      docker,
      t0 + docker.maxRestarts * (docker.maxBackoffMs + 1)
    ).state;

    const midOpen = registerRestartAttempt(
      state,
      docker,
      (state.openUntil ?? 0) - 1
    );
    expect(midOpen.allowed).toBe(false);
    expect(midOpen.reason).toBe("circuit_open");
  });
});
