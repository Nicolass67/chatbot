import { describe, expect, it } from "vitest";
import { buildObjectiveContext } from "@/lib/request-router/objective-context";
import { classifyMemoryIntent } from "./intent-classifier-runtime";
import {
  buildMemoryClassifierUserPrompt,
  parseMemoryIntentClassification,
} from "./intent-classifier";

describe("parseMemoryIntentClassification", () => {
  it("parse un JSON valide avec mémoires", () => {
    const parsed = parseMemoryIntentClassification(
      JSON.stringify({
        shouldRemember: true,
        memories: [
          {
            content: "Préfère les réponses concises en français",
            category: "preference",
            importance: 0.85,
          },
        ],
        confidence: 0.9,
        reason: "Préférence explicite",
      })
    );

    expect(parsed.shouldRemember).toBe(true);
    expect(parsed.memories).toHaveLength(1);
    expect(parsed.memories[0].category).toBe("preference");
  });

  it("extrait le JSON depuis un bloc markdown", () => {
    const parsed = parseMemoryIntentClassification(
      'Voici:\n```json\n{"shouldRemember":false,"memories":[],"confidence":0.8,"reason":"Question générale"}\n```'
    );
    expect(parsed.shouldRemember).toBe(false);
  });
});

describe("buildMemoryClassifierUserPrompt", () => {
  it("inclut le message et le mode", () => {
    const objective = buildObjectiveContext({
      message: "Je préfère les réponses courtes",
      webSearchEnabled: true,
      chatMode: "chat",
      imageCount: 0,
      attachmentCount: 0,
      modelId: "",
    });
    const prompt = buildMemoryClassifierUserPrompt(objective);
    expect(prompt).toContain("Je préfère les réponses courtes");
    expect(prompt).toContain("Mode: chat");
  });
});

describe("classifyMemoryIntent", () => {
  it("sans runtime LLM → pas de fast path lexical", async () => {
    const decision = await classifyMemoryIntent(
      {
        message: "Retiens que je travaille sur un chatbot local",
        webSearchEnabled: true,
        chatMode: "chat",
        imageCount: 0,
        attachmentCount: 0,
        modelId: "",
      },
      undefined,
      { memoryEnabled: true }
    );

    expect(decision.shouldRemember).toBe(false);
    expect(decision.source).toBe("none");
  });

  it("retourne disabled si mémoire off", async () => {
    const decision = await classifyMemoryIntent(
      {
        message: "Retiens que j'aime le café",
        webSearchEnabled: true,
        chatMode: "chat",
        imageCount: 0,
        attachmentCount: 0,
        modelId: "",
      },
      undefined,
      { memoryEnabled: false }
    );

    expect(decision.shouldRemember).toBe(false);
    expect(decision.source).toBe("disabled");
  });

  it("filet déterministe: déménagement sans runtime LLM", async () => {
    const decision = await classifyMemoryIntent(
      {
        message: "Je vais déménager à Strasbourg le 12 septembre",
        webSearchEnabled: true,
        chatMode: "chat",
        imageCount: 0,
        attachmentCount: 0,
        modelId: "",
      },
      undefined,
      { memoryEnabled: true }
    );

    expect(decision.shouldRemember).toBe(true);
    expect(decision.source).toBe("fast_path");
    expect(decision.memories.some((m) => /Strasbourg/i.test(m.content))).toBe(
      true
    );
  });
});


describe("parseMemoryIntentClassification coercion", () => {
  it("accepte memories comme tableau de chaines", () => {
    const parsed = parseMemoryIntentClassification(
      JSON.stringify({
        shouldRemember: true,
        memories: ["L'utilisateur a 26 ans"],
        confidence: 0.9,
        reason: "age",
      })
    );
    expect(parsed.shouldRemember).toBe(true);
    expect(parsed.memories).toHaveLength(1);
    expect(parsed.memories[0].content).toContain("26");
    expect(parsed.memories[0].category).toBe("other");
  });
});
