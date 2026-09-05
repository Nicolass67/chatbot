import { describe, expect, it } from "vitest";
import {
  validateMemoryDecisions,
  MEMORY_MIN_CONFIDENCE,
} from "./validator";
import type {
  ExistingMemorySnippet,
  MemoryDecisionPayload,
} from "./types";

const existing: ExistingMemorySnippet[] = [
  {
    id: "mem-hwinfo",
    content: "L'utilisateur préfère HWiNFO64 pour ses benchmarks.",
    category: "preference",
    importance: 0.9,
  },
];

function payload(
  candidates: MemoryDecisionPayload["candidates"]
): MemoryDecisionPayload {
  return { candidates };
}

describe("validateMemoryDecisions", () => {
  it("accepte une préférence explicite durable (CREATE)", () => {
    const result = validateMemoryDecisions(
      payload([
        {
          action: "create",
          memoryType: "preference",
          content: "L'utilisateur préfère les réponses concises en français.",
          existingMemoryId: null,
          confidence: 0.95,
          reason: "préférence explicite",
        },
      ]),
      []
    );
    expect(result).toHaveLength(1);
    expect(result[0].accepted).toBe(true);
    expect(result[0].action).toBe("create");
  });

  it("ignore une info sans valeur future (confidence faible)", () => {
    const result = validateMemoryDecisions(
      payload([
        {
          action: "create",
          memoryType: "other",
          content: "L'utilisateur a faim ce soir.",
          existingMemoryId: null,
          confidence: 0.4,
          reason: "temporaire",
        },
      ]),
      []
    );
    expect(result[0].accepted).toBe(false);
    expect(result[0].rejectReason).toBe("confidence_below_threshold");
  });

  it("ignore confidence juste sous le seuil", () => {
    const result = validateMemoryDecisions(
      payload([
        {
          action: "create",
          memoryType: "fact",
          content: "L'utilisateur mentionne peut-être aimer le thé.",
          existingMemoryId: null,
          confidence: MEMORY_MIN_CONFIDENCE - 0.01,
          reason: "incertain",
        },
      ]),
      []
    );
    expect(result[0].accepted).toBe(false);
  });

  it("convertit un CREATE doublon en UPDATE", () => {
    const result = validateMemoryDecisions(
      payload([
        {
          action: "create",
          memoryType: "preference",
          content: "L'utilisateur préfère HWiNFO64 pour ses benchmarks SSD.",
          existingMemoryId: null,
          confidence: 0.92,
          reason: "doublon proche",
        },
      ]),
      existing
    );
    expect(result[0].accepted).toBe(true);
    expect(result[0].action).toBe("update");
    expect(result[0].existingMemoryId).toBe("mem-hwinfo");
  });

  it("accepte UPDATE d'une préférence existante", () => {
    const result = validateMemoryDecisions(
      payload([
        {
          action: "update",
          memoryType: "preference",
          content: "L'utilisateur préfère OCCT pour ses benchmarks.",
          existingMemoryId: "mem-hwinfo",
          confidence: 0.93,
          reason: "changement de préférence",
        },
      ]),
      existing
    );
    expect(result[0].accepted).toBe(true);
    expect(result[0].action).toBe("update");
  });

  it("refuse les secrets", () => {
    const result = validateMemoryDecisions(
      payload([
        {
          action: "create",
          memoryType: "other",
          content: "Le mot de passe Wi-Fi de l'utilisateur est Secret123!",
          existingMemoryId: null,
          confidence: 0.99,
          reason: "secret",
        },
      ]),
      []
    );
    expect(result[0].accepted).toBe(false);
    expect(result[0].rejectReason).toBe("secret_or_sensitive");
  });

  it("refuse UPDATE avec id inconnu (confidence moyenne)", () => {
    const result = validateMemoryDecisions(
      payload([
        {
          action: "update",
          memoryType: "fact",
          content: "L'utilisateur habite maintenant à Lyon.",
          existingMemoryId: "unknown-id",
          confidence: 0.8,
          reason: "id manquant",
        },
      ]),
      existing
    );
    expect(result[0].accepted).toBe(false);
    expect(result[0].rejectReason).toBe("missing_or_unknown_existing_id");
  });

  it("ignore action ignore", () => {
    const result = validateMemoryDecisions(
      payload([
        {
          action: "ignore",
          memoryType: "other",
          content: "rien à retenir ici vraiment",
          existingMemoryId: null,
          confidence: 0.99,
          reason: "noop",
        },
      ]),
      []
    );
    expect(result[0].accepted).toBe(false);
    expect(result[0].rejectReason).toBe("ignore");
  });
});
