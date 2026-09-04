/**
 * Closes incomplete Markdown structures during streaming to avoid layout breaks.
 * Only applies lightweight fixes — incomplete bold/italic stays as plain text.
 */
export function stabilizeStreamingMarkdown(source: string): string {
  if (!source) return source;

  let text = source;

  const fencePattern = /(^|\n)(```+|~~~+)/g;
  const fenceMatches = [...text.matchAll(fencePattern)];
  if (fenceMatches.length % 2 === 1) {
    const lastFence = fenceMatches[fenceMatches.length - 1][2];
    text += `\n${lastFence}`;
  }

  const inlineDollarCount = (text.match(/(?<!\$)\$(?!\$)/g) ?? []).length;
  if (inlineDollarCount % 2 === 1) {
    text += "$";
  }

  const blockDollarCount = (text.match(/\$\$/g) ?? []).length;
  if (blockDollarCount % 2 === 1) {
    text += "\n$$";
  }

  const lines = text.split("\n");
  const lastLine = lines[lines.length - 1] ?? "";
  if (/^\|.+\|$/.test(lastLine.trim()) && !lastLine.includes("---")) {
    // Table row in progress — no change needed; GFM handles partial tables.
  }

  return text;
}
