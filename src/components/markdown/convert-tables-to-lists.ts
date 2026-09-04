function isTableRow(line: string): boolean {
  const trimmed = line.trim();
  return trimmed.startsWith("|") && trimmed.endsWith("|") && trimmed.length > 2;
}

function parseTableRow(line: string): string[] {
  return line
    .trim()
    .slice(1, -1)
    .split("|")
    .map((cell) => cell.trim());
}

function isSeparatorRow(cells: string[]): boolean {
  return cells.length > 0 && cells.every((cell) => /^:?-{3,}:?$/.test(cell));
}

function isCompleteTable(tableLines: string[]): boolean {
  return tableLines.map(parseTableRow).some((cells) => isSeparatorRow(cells));
}

function tableToReadableBlocks(tableLines: string[]): string[] {
  const rows = tableLines.map(parseTableRow);
  let headers: string[] | null = null;
  const dataRows: string[][] = [];

  for (const cells of rows) {
    if (isSeparatorRow(cells)) continue;
    if (!headers) {
      headers = cells;
      continue;
    }
    dataRows.push(cells);
  }

  if (!headers || dataRows.length === 0) {
    return tableLines;
  }

  const output: string[] = [];

  if (headers.length === 2) {
    for (const row of dataRows) {
      const [left, right] = row;
      if (left && right) {
        output.push(`- **${left}** : ${right}`);
      } else if (left) {
        output.push(`- ${left}`);
      }
    }
    return output;
  }

  for (const row of dataRows) {
    const title = row[0]?.trim();
    if (!title) continue;

    if (headers.length === 2) {
      output.push(`- **${title}** : ${row[1] ?? "—"}`);
      continue;
    }

    output.push(`**${title}**`);
    for (let col = 1; col < headers.length; col++) {
      const label = headers[col]?.trim();
      const value = row[col]?.trim();
      if (!label || !value) continue;
      output.push(`- **${label}** : ${value}`);
    }
    output.push("");
  }

  return output;
}

/**
 * Converts GFM markdown tables into bullet lists for narrow chat layouts.
 * Skips fenced code blocks.
 */
export function convertMarkdownTablesToLists(markdown: string): string {
  const lines = markdown.split("\n");
  const result: string[] = [];
  let inFence = false;
  let fenceMarker = "";
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];
    const trimmed = line.trim();

    if (trimmed.startsWith("```")) {
      if (!inFence) {
        inFence = true;
        fenceMarker = trimmed;
      } else if (trimmed === fenceMarker || trimmed === "```") {
        inFence = false;
        fenceMarker = "";
      }
      result.push(line);
      i++;
      continue;
    }

    if (!inFence && isTableRow(line)) {
      const tableLines: string[] = [];
      while (i < lines.length && isTableRow(lines[i])) {
        tableLines.push(lines[i]);
        i++;
      }

      if (isCompleteTable(tableLines)) {
        const converted = tableToReadableBlocks(tableLines);
        if (converted.length > 0) {
          if (result.length > 0 && result[result.length - 1] !== "") {
            result.push("");
          }
          result.push(...converted);
          continue;
        }
      }

      result.push(...tableLines);
      continue;
    }

    result.push(line);
    i++;
  }

  return result.join("\n");
}
