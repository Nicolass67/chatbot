import { describe, expect, it } from "vitest";
import {
  assertTransition,
  canTransition,
  isTerminalStatus,
} from "./state-machine";
import type { ActionStatus } from "./types";

describe("action state machine", () => {
  it("autorise proposed → pending_confirmation", () => {
    expect(canTransition("proposed", "pending_confirmation")).toBe(true);
  });

  it("autorise pending_confirmation → confirmed", () => {
    expect(canTransition("pending_confirmation", "confirmed")).toBe(true);
  });

  it("autorise confirmed → executing → completed", () => {
    expect(canTransition("confirmed", "executing")).toBe(true);
    expect(canTransition("executing", "completed")).toBe(true);
  });

  it("refuse pending_confirmation → completed (saut d'état)", () => {
    expect(canTransition("pending_confirmation", "completed")).toBe(false);
  });

  it("refuse completed → executing (état terminal)", () => {
    expect(canTransition("completed", "executing")).toBe(false);
  });

  it("refuse executing → pending_confirmation", () => {
    expect(canTransition("executing", "pending_confirmation")).toBe(false);
  });

  it("marque les états terminaux", () => {
    const terminals: ActionStatus[] = [
      "completed",
      "rejected",
      "cancelled",
      "expired",
      "failed",
    ];
    for (const status of terminals) {
      expect(isTerminalStatus(status)).toBe(true);
    }
    expect(isTerminalStatus("pending_confirmation")).toBe(false);
  });

  it("assertTransition lève sur transition invalide", () => {
    expect(() => assertTransition("completed", "executing")).toThrow(
      /Transition d'action invalide/
    );
  });
});
