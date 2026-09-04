import { describe, expect, it } from "vitest";
import { normalizeMathMarkdown } from "./normalize-math-markdown";

describe("normalizeMathMarkdown", () => {
  it("convertit (^{235})U en formule inline", () => {
    const input =
      "séparer les isotopes (^{235})U et (^{238})U en exploitant la différence de masse.";
    const result = normalizeMathMarkdown(input);
    expect(result).toContain("$^{235}U$");
    expect(result).toContain("$^{238}U$");
  });

  it("convertit \\(...\\) en $...$", () => {
    expect(normalizeMathMarkdown(String.raw`Formule \(\frac{a}{b}\) ici`)).toContain(
      "$\\frac{a}{b}$"
    );
  });

  it("laisse le contenu déjà délimité intact", () => {
    const input = "Déjà ok : $E=mc^2$";
    expect(normalizeMathMarkdown(input)).toBe(input);
  });
});
