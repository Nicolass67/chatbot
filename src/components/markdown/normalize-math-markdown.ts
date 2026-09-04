/**
 * Normalise les formules LaTeX fréquentes des LLM (souvent sans délimiteurs $).
 */
export function normalizeMathMarkdown(source: string): string {
  if (!source) return source;

  let text = source;

  // \( ... \) et \[ ... \] → délimiteurs remark-math
  text = text.replace(/\\\(([\s\S]+?)\\\)/g, (_, expr) => `$${expr.trim()}$`);
  text = text.replace(/\\\[([\s\S]+?)\\\]/g, (_, expr) => `$$\n${expr.trim()}\n$$`);

  // (^{235})U → $^{235}U$
  text = text.replace(
    /\(\s*\^\{([^}]+)\}\s*\)\s*([A-Za-z]{1,4})\b/g,
    (_, sup, sym) => `$^{${sup}}${sym}$`
  );

  // ^{235}U (sans parenthèses)
  text = text.replace(
    /(?<![\\$])\^\{([^}]+)\}\s*([A-Za-z]{1,4})\b/g,
    (_, sup, sym) => `$^{${sup}}${sym}$`
  );

  // _{92}U (isotopes / indices)
  text = text.replace(
    /(?<![\\$])_\{([^}]+)\}\s*([A-Za-z]{1,4})\b/g,
    (_, sub, sym) => `$_{${sub}}${sym}$`
  );

  return text;
}
