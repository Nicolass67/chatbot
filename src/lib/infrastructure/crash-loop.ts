import type { ServiceDefinition } from "./types";

export interface CrashLoopState {
  serviceId: string;
  restarts: number[];
  circuitOpen: boolean;
  openUntil: number | null;
  lastRestartAt: number | null;
}

export function createCrashLoopState(serviceId: string): CrashLoopState {
  return {
    serviceId,
    restarts: [],
    circuitOpen: false,
    openUntil: null,
    lastRestartAt: null,
  };
}

/** Record a restart attempt; returns whether restart is allowed now. */
export function registerRestartAttempt(
  state: CrashLoopState,
  def: ServiceDefinition,
  now = Date.now()
): { allowed: boolean; state: CrashLoopState; backoffMs: number; reason?: string } {
  // Clear expired circuit
  if (state.circuitOpen && state.openUntil && now >= state.openUntil) {
    state = {
      ...state,
      circuitOpen: false,
      openUntil: null,
      restarts: [],
    };
  }

  if (state.circuitOpen) {
    return {
      allowed: false,
      state,
      backoffMs: Math.max(0, (state.openUntil ?? now) - now),
      reason: "circuit_open",
    };
  }

  const windowStart = now - def.restartWindowMs;
  const recent = state.restarts.filter((t) => t >= windowStart);

  if (recent.length >= def.maxRestarts) {
    const openUntil = now + def.maxBackoffMs;
    return {
      allowed: false,
      state: {
        ...state,
        restarts: recent,
        circuitOpen: true,
        openUntil,
      },
      backoffMs: def.maxBackoffMs,
      reason: "max_restarts_exceeded",
    };
  }

  const attempt = recent.length;
  const backoffMs = Math.min(
    def.maxBackoffMs,
    def.baseBackoffMs * Math.pow(2, attempt)
  );

  if (state.lastRestartAt && now - state.lastRestartAt < backoffMs) {
    return {
      allowed: false,
      state: { ...state, restarts: recent },
      backoffMs: backoffMs - (now - state.lastRestartAt),
      reason: "backoff",
    };
  }

  return {
    allowed: true,
    state: {
      ...state,
      restarts: [...recent, now],
      lastRestartAt: now,
      circuitOpen: false,
      openUntil: null,
    },
    backoffMs,
  };
}

export function noteSuccessfulRecovery(state: CrashLoopState): CrashLoopState {
  return {
    ...state,
    restarts: [],
    circuitOpen: false,
    openUntil: null,
  };
}
