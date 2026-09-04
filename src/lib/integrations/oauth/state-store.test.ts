import { afterEach, describe, expect, it } from "vitest";
import {
  clearOAuthStateStore,
  consumeOAuthState,
  createOAuthState,
} from "./state-store";

describe("oauth state store", () => {
  afterEach(() => {
    clearOAuthStateStore();
  });

  it("crée et consomme un state valide", () => {
    const state = createOAuthState("user-1", "gmail");
    const consumed = consumeOAuthState(state, "gmail");
    expect(consumed).toEqual({ userId: "user-1" });
  });

  it("refuse double consommation", () => {
    const state = createOAuthState("user-1", "gmail");
    expect(consumeOAuthState(state, "gmail")).not.toBeNull();
    expect(consumeOAuthState(state, "gmail")).toBeNull();
  });

  it("refuse un state inconnu", () => {
    expect(consumeOAuthState("invalid", "gmail")).toBeNull();
  });
});
