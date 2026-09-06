/**
 * Semaphore global LM Studio — évite extract + synthèse concurrente non bornée.
 * Pour extractionConcurrency=2, configurer LM Studio Max Concurrent Predictions >= 2.
 */

let limit = Math.max(1, Number(process.env.LM_STUDIO_MAX_INFLIGHT || 2) || 2);
let active = 0;
const waiters: Array<() => void> = [];

export function setLmStudioInflightLimit(n: number): void {
  limit = Math.max(1, Math.min(8, Math.floor(n)));
  flush();
}

export function getLmStudioInflightLimit(): number {
  return limit;
}

export function getLmStudioInflightActive(): number {
  return active;
}

function flush(): void {
  while (active < limit && waiters.length > 0) {
    const next = waiters.shift();
    if (next) next();
  }
}

export async function withLmStudioGate<T>(fn: () => Promise<T>): Promise<T> {
  if (active >= limit) {
    await new Promise<void>((resolve) => waiters.push(resolve));
  }
  active += 1;
  try {
    return await fn();
  } finally {
    active -= 1;
    flush();
  }
}
