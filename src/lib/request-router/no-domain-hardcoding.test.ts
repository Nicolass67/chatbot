import { describe, expect, it } from "vitest";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const ROOT = join(process.cwd(), "src", "lib");

const SCAN_DIRS = [
  join(ROOT, "agent"),
  join(ROOT, "request-router"),
  join(ROOT, "tools", "web-search"),
];

const EXCLUDED_FILES = new Set([
  "evaluation-dataset.ts",
]);

const BANNED_PATTERNS: Array<{ label: string; pattern: RegExp }> = [
  { label: "bitcoin", pattern: /\bbitcoin\b/i },
  { label: "ethereum", pattern: /\bethereum\b/i },
  { label: "coinmarketcap", pattern: /coinmarketcap/i },
  { label: "kraken", pattern: /\bkraken\b/i },
  { label: "requiresMarketDiscovery", pattern: /requiresMarketDiscovery/ },
  { label: "isFinancialLiveDataQuery", pattern: /isFinancialLiveDataQuery/ },
  { label: "FINANCIAL_LIVE_DATA", pattern: /FINANCIAL_LIVE_DATA/ },
  { label: "MARKET_REQUEST_PATTERNS", pattern: /MARKET_REQUEST_PATTERNS/ },
  { label: "isProductSpecificQuery", pattern: /isProductSpecificQuery/ },
  { label: "registerDiscoveryResults", pattern: /registerDiscoveryResults/ },
  { label: "MODEL_LIKE_PATTERN", pattern: /MODEL_LIKE_PATTERN/ },
  { label: "live-data-intent", pattern: /live-data-intent/ },
  { label: "market-discovery", pattern: /market-discovery/ },
];

function collectTsFiles(dir: string): string[] {
  const entries = readdirSync(dir);
  const files: string[] = [];
  for (const entry of entries) {
    const full = join(dir, entry);
    const stat = statSync(full);
    if (stat.isDirectory()) {
      files.push(...collectTsFiles(full));
    } else if (entry.endsWith(".ts") && !entry.endsWith(".test.ts")) {
      if (!EXCLUDED_FILES.has(entry)) {
        files.push(full);
      }
    }
  }
  return files;
}

describe("no domain hardcoding in production routing/agent/web-search code", () => {
  it("ne contient pas de références métier interdites", () => {
    const files = SCAN_DIRS.flatMap(collectTsFiles);
    const violations: string[] = [];

    for (const file of files) {
      const content = readFileSync(file, "utf8");
      const rel = relative(process.cwd(), file);

      for (const { label, pattern } of BANNED_PATTERNS) {
        if (pattern.test(content)) {
          violations.push(`${rel} → ${label}`);
        }
      }
    }

    expect(violations).toEqual([]);
  });

  it("le code de production ne mentionne pas uranium (domaine inédit test-only)", () => {
    const files = SCAN_DIRS.flatMap(collectTsFiles);
    const hits = files.filter((file) =>
      /\buranium\b/i.test(readFileSync(file, "utf8"))
    );
    expect(hits.map((f) => relative(process.cwd(), f))).toEqual([]);
  });
});
