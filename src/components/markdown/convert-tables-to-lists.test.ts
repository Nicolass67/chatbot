import { describe, expect, it } from "vitest";
import { convertMarkdownTablesToLists } from "./convert-tables-to-lists";

describe("convertMarkdownTablesToLists", () => {
  it("convertit un tableau clé/valeur en liste", () => {
    const input = `Intro

| Métrique | Valeur |
| --- | --- |
| Prix | 42 € |
| Stock | Oui |

Fin`;

    expect(convertMarkdownTablesToLists(input)).toBe(`Intro

- **Prix** : 42 €
- **Stock** : Oui

Fin`);
  });

  it("convertit un tableau multi-colonnes en blocs titrés", () => {
    const input = `| Produit | Prix | Stock |
| --- | --- | --- |
| GPU A | 500 € | Oui |
| GPU B | 450 € | Non |`;

    expect(convertMarkdownTablesToLists(input)).toBe(`**GPU A**
- **Prix** : 500 €
- **Stock** : Oui

**GPU B**
- **Prix** : 450 €
- **Stock** : Non
`);
  });

  it("ignore les tableaux dans les blocs de code", () => {
    const input = `\`\`\`md
| A | B |
| - | - |
\`\`\``;

    expect(convertMarkdownTablesToLists(input)).toBe(input);
  });

  it("laisse un tableau incomplet (stream) tel quel", () => {
    const input = `| Col1 | Col2 |
| --- |`;

    expect(convertMarkdownTablesToLists(input)).toBe(input);
  });
});
