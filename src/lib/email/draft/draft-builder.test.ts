import { describe, expect, it } from "vitest";
import {
  buildEmailDraftInstructionsBlock,
  injectEmailDraftWritingIntoContext,
} from "./draft-builder";
import { formatWritingPreferencesBlock } from "./writing-prefs";

describe("email draft builder", () => {
  it("formatWritingPreferencesBlock inclut les préférences", () => {
    const block = formatWritingPreferencesBlock([
      {
        id: "m1",
        content: "Tutoyer les collègues",
        category: "communication",
        importance: 0.9,
      },
    ]);

    expect(block).toContain("email_writing_preferences");
    expect(block).toContain("Tutoyer les collègues");
  });

  it("injectEmailDraftWritingIntoContext enrichit le system prompt", () => {
    const messages = [{ role: "system" as const, content: "Base prompt" }];
    injectEmailDraftWritingIntoContext(
      messages,
      formatWritingPreferencesBlock([])
    );

    expect(messages[0]?.content).toContain("email_draft_instructions");
    expect(buildEmailDraftInstructionsBlock("prefs")).toContain("email_create_draft");
    expect(
      buildEmailDraftInstructionsBlock("prefs", {
        accountEmail: "me@gmail.com",
      })
    ).toContain("me@gmail.com");
    expect(buildEmailDraftInstructionsBlock("prefs")).toContain(
      "INTERDIT de dire que tu ne peux pas envoyer"
    );
  });
});
