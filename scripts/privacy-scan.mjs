#!/usr/bin/env node
/**
 * Privacy scan — fail if personal infra / secret-looking strings appear
 * in tracked (or scanned) source. Does not need network or secrets.
 *
 * Usage: node scripts/privacy-scan.mjs
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

/** Exact personal / infra strings that must never be published. */
const FORBIDDEN_LITERALS = [
  "rousseau-nicolas67",
  "nicolazer67.freeboxos.fr",
  "bold-shadow-4872",
  "D8:43:AE:1E:09:56",
  "C:\\Users\\nicolazer",
  "C:/Users/nicolazer",
  "Users\\nicolazer",
  "Users/nicolazer",
  "cedb43f381244210a5a4dd7022f2a6d3",
  "01a05e4d-8371-7940-8bb3-90a0412b36d4",
  "fzkzrj11.fbxos.fr",
  "Nicolass67/local-ai-chat",
];

/**
 * Crypto / token shapes. Avoid matching docs that only name the concept
 * (e.g. "never commit BEGIN PRIVATE KEY") — require material after the header,
 * or a non-placeholder token body.
 */
const FORBIDDEN_PATTERNS = [
  {
    name: "cfast_service_token",
    // Real CF Access service tokens are long; skip obvious placeholders.
    re: /\bcfast_[A-Za-z0-9]{20,}\b/g,
    allow: (m) => /^cfast_x+$/i.test(m) || /cfast_\.+/i.test(m),
  },
  {
    name: "github_pat_classic",
    re: /\bghp_[A-Za-z0-9]{20,}\b/g,
    allow: () => false,
  },
  {
    name: "github_pat_fine",
    re: /\bgithub_pat_[A-Za-z0-9_]{20,}\b/g,
    allow: () => false,
  },
  {
    name: "private_key_block",
    re: /-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]+/g,
    allow: () => false,
  },
];

const SKIP_DIR_NAMES = new Set([
  ".git",
  "node_modules",
  ".next",
  "data",
  "sidestore-prep",
  "artifacts",
  "coverage",
  "derived",
  "derived-sim",
  "target",
  ".turbo",
  ".cache",
  "Pods",
]);

const SKIP_FILE_NAMES = new Set([
  "privacy-scan.mjs", // this file lists forbidden strings on purpose
]);

const TEXT_EXT = new Set([
  ".ts",
  ".tsx",
  ".js",
  ".mjs",
  ".cjs",
  ".json",
  ".jsonc",
  ".swift",
  ".md",
  ".yml",
  ".yaml",
  ".html",
  ".htm",
  ".css",
  ".txt",
  ".example",
  ".plist",
  ".xcconfig",
  ".env",
  ".svg",
  ".sh",
  ".ps1",
  ".py",
  ".rs",
  ".toml",
]);

function shouldScanFile(rel) {
  const base = path.basename(rel);
  if (SKIP_FILE_NAMES.has(base)) return false;
  if (base === "mcp.json") return false; // local only
  if (base.endsWith(".local.json") || base.endsWith(".local.jsonc")) return false;
  if (base === "Local.xcconfig") return false;
  if (base === "wrangler.local.jsonc") return false;
  if (base === "capacitor.local.json") return false;
  if (base === "tunnel.env" || base === "machine.env" || base === "cloudflare-api.env") {
    return false;
  }
  const ext = path.extname(base).toLowerCase();
  if (!ext) {
    // Allow extensionless text-ish tracked names
    return ["Dockerfile", "Makefile", "LICENSE", "AGENTS.md"].includes(base);
  }
  return TEXT_EXT.has(ext) || base.endsWith(".env.example");
}

function listTrackedFiles() {
  const r = spawnSync("git", ["ls-files", "-z"], {
    cwd: ROOT,
    encoding: "buffer",
    shell: false,
  });
  if (r.status !== 0) {
    throw new Error("git ls-files failed");
  }
  const raw = r.stdout.toString("utf8");
  return raw.split("\0").filter(Boolean);
}

function walkUntrackedButPresent(relDir, out) {
  const abs = path.join(ROOT, relDir);
  if (!fs.existsSync(abs)) return;
  for (const ent of fs.readdirSync(abs, { withFileTypes: true })) {
    if (SKIP_DIR_NAMES.has(ent.name)) continue;
    const rel = path.join(relDir, ent.name).replace(/\\/g, "/");
    if (ent.isDirectory()) walkUntrackedButPresent(rel, out);
    else if (shouldScanFile(rel)) out.push(rel);
  }
}

function collectFiles() {
  const tracked = listTrackedFiles().filter((f) => {
    const parts = f.split("/");
    if (parts.some((p) => SKIP_DIR_NAMES.has(p))) return false;
    return shouldScanFile(f);
  });
  // Also scan common source roots for dirty untracked leaks (except ignored locals).
  const extra = [];
  for (const d of ["src", "scripts", "apps", "workers", "docs", "www", ".github", "deploy", "contracts"]) {
    walkUntrackedButPresent(d, extra);
  }
  return [...new Set([...tracked, ...extra])];
}

function scanFile(rel) {
  const abs = path.join(ROOT, rel);
  let text;
  try {
    text = fs.readFileSync(abs, "utf8");
  } catch {
    return [];
  }
  if (text.includes("\0")) return []; // binary

  const hits = [];
  for (const lit of FORBIDDEN_LITERALS) {
    if (text.includes(lit)) {
      const lineNo = text.split(/\r?\n/).findIndex((l) => l.includes(lit)) + 1;
      hits.push({ rel, line: lineNo, kind: "literal", detail: lit });
    }
  }
  for (const { name, re, allow } of FORBIDDEN_PATTERNS) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(text))) {
      const matched = m[0];
      if (allow(matched)) continue;
      const before = text.slice(0, m.index);
      const lineNo = before.split(/\r?\n/).length;
      const masked =
        matched.length > 12
          ? `${matched.slice(0, 8)}…(${matched.length} chars)`
          : matched;
      hits.push({ rel, line: lineNo, kind: name, detail: masked });
    }
  }
  return hits;
}

function main() {
  const files = collectFiles();
  const allHits = [];
  for (const f of files) {
    allHits.push(...scanFile(f));
  }

  if (allHits.length) {
    console.error("privacy-scan FAILED — personal/secret-looking content found:\n");
    for (const h of allHits) {
      console.error(`  ${h.rel}:${h.line}  [${h.kind}]  ${h.detail}`);
    }
    console.error(`\n${allHits.length} hit(s) in ${files.length} scanned file(s).`);
    process.exit(1);
  }

  console.log(
    `privacy-scan OK — ${files.length} file(s), no forbidden personal/secret patterns.`
  );
}

main();
