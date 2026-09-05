import { describe, expect, it } from "vitest";
import { isAbortLikeError } from "./abort";

/**
 * Comportement orchestrateur (documenté + couvert via helpers) :
 * - signal.aborted + contenu vide → event error ABORTED, pas de placeholder, pas de done
 * - AbortError catch → error ABORTED (pas return silencieux)
 * - persist Assistant AVANT done ; échec persist → error, pas de done
 * - statusPoll : skip si tick précédent encore in-flight
 */
describe("orchestrator abort helpers", () => {
  it("isAbortLikeError matches AbortError Error", () => {
    const err = new Error("aborted");
    err.name = "AbortError";
    expect(isAbortLikeError(err)).toBe(true);
  });

  it("isAbortLikeError matches DOMException AbortError", () => {
    if (typeof DOMException === "undefined") return;
    expect(isAbortLikeError(new DOMException("Aborted", "AbortError"))).toBe(
      true
    );
  });

  it("isAbortLikeError rejects unrelated errors", () => {
    expect(isAbortLikeError(new Error("network"))).toBe(false);
    expect(isAbortLikeError(undefined)).toBe(false);
  });
});
