import { describe, expect, it, vi } from "vitest";
import {
  applyEditToLocalMessages,
  canStartEditingMessage,
  handleEditTextareaKeyDown,
} from "@/components/chat/user-message-edit";

describe("user-message-edit", () => {
  const sample = [
    { id: "u1", role: "user", content: "A" },
    { id: "a1", role: "assistant", content: "B" },
    { id: "u2", role: "user", content: "C" },
    { id: "a2", role: "assistant", content: "D" },
  ];

  it("autorise l'édition sur mobile et desktop hors génération", () => {
    expect(canStartEditingMessage(sample[0], false)).toBe(true);
    expect(canStartEditingMessage(sample[0], true)).toBe(false);
    expect(canStartEditingMessage(sample[1], false)).toBe(false);
    expect(
      canStartEditingMessage(
        { id: "pending-user-1", role: "user", content: "x" },
        false
      )
    ).toBe(false);
  });

  it("tronque les messages locaux après édition", () => {
    const next = applyEditToLocalMessages(sample, "u1", "A modifié");
    expect(next).toHaveLength(1);
    expect(next[0].content).toBe("A modifié");
  });

  it("Enter envoie, Shift+Enter laisse le retour à la ligne", () => {
    const submit = vi.fn();
    handleEditTextareaKeyDown(
      { key: "Enter", shiftKey: false, preventDefault: vi.fn() },
      submit
    );
    expect(submit).toHaveBeenCalledOnce();

    submit.mockClear();
    handleEditTextareaKeyDown(
      { key: "Enter", shiftKey: true, preventDefault: vi.fn() },
      submit
    );
    expect(submit).not.toHaveBeenCalled();
  });
});
