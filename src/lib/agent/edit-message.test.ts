import { describe, expect, it } from "vitest";
import {
  buildContextMessagesAfterEdit,
  canSubmitEditedMessage,
  getDescendantMessageIds,
  shouldInvalidateSummary,
} from "@/lib/agent/edit-message-utils";

const ordered = [
  { id: "m1", role: "user", createdAt: "1" },
  { id: "m2", role: "assistant", createdAt: "2" },
  { id: "m3", role: "user", createdAt: "3" },
  { id: "m4", role: "assistant", createdAt: "4" },
  { id: "m5", role: "user", createdAt: "5" },
];

describe("edit-message", () => {
  it("retourne les messages descendants à supprimer", () => {
    expect(getDescendantMessageIds(ordered, "m3")).toEqual(["m4", "m5"]);
    expect(getDescendantMessageIds(ordered, "m5")).toEqual([]);
    expect(getDescendantMessageIds(ordered, "unknown")).toEqual([]);
  });

  it("construit le contexte sans les messages après l'édition", () => {
    expect(buildContextMessagesAfterEdit(ordered, "m3").map((m) => m.id)).toEqual([
      "m1",
      "m2",
      "m3",
    ]);
  });

  it("refuse un message vide sans pièce jointe", () => {
    expect(canSubmitEditedMessage("", 0)).toBe(false);
    expect(canSubmitEditedMessage("   ", 0)).toBe(false);
    expect(canSubmitEditedMessage("Bonjour", 0)).toBe(true);
    expect(canSubmitEditedMessage("", 1)).toBe(true);
  });

  it("invalide le résumé si un message supprimé était couvert", () => {
    expect(
      shouldInvalidateSummary("m4", "m3", ["m4", "m5"], ordered)
    ).toBe(true);
    expect(
      shouldInvalidateSummary("m2", "m3", ["m4", "m5"], ordered)
    ).toBe(false);
    expect(
      shouldInvalidateSummary("m1", "m1", ["m2"], ordered)
    ).toBe(true);
  });
});
