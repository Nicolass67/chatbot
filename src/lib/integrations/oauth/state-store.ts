import { nanoid } from "nanoid";

const STATE_TTL_MS = 10 * 60 * 1000;

interface OAuthStateEntry {
  userId: string;
  provider: "gmail";
  expiresAt: number;
}

const stateStore = new Map<string, OAuthStateEntry>();

export function createOAuthState(
  userId: string,
  provider: "gmail" = "gmail"
): string {
  purgeExpiredStates();
  const state = nanoid(32);
  stateStore.set(state, {
    userId,
    provider,
    expiresAt: Date.now() + STATE_TTL_MS,
  });
  return state;
}

export function consumeOAuthState(
  state: string,
  expectedProvider: "gmail" = "gmail"
): { userId: string } | null {
  purgeExpiredStates();
  const entry = stateStore.get(state);
  stateStore.delete(state);

  if (!entry) return null;
  if (entry.expiresAt <= Date.now()) return null;
  if (entry.provider !== expectedProvider) return null;

  return { userId: entry.userId };
}

function purgeExpiredStates() {
  const now = Date.now();
  for (const [key, entry] of stateStore.entries()) {
    if (entry.expiresAt <= now) {
      stateStore.delete(key);
    }
  }
}

/** Test-only */
export function clearOAuthStateStore() {
  stateStore.clear();
}

export function peekOAuthStateCount(): number {
  purgeExpiredStates();
  return stateStore.size;
}
