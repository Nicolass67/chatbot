#!/usr/bin/env node
/**
 * Télécharge llama.xcframework (llama.cpp nightly) dans apps/ios/Vendor/.
 * Ne commit jamais le binaire — gitignored.
 *
 * Usage: npm.cmd run ios:fetch-llama
 * Env: LLAMA_XCFRAMEWORK_TAG / LLAMA_XCFRAMEWORK_URL (override optionnel)
 */
import { createWriteStream, existsSync, mkdirSync, readFileSync, rmSync, readdirSync, renameSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { pipeline } from "node:stream/promises";
import { execSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..", "..");
const vendorDir = join(root, "apps", "ios", "Vendor");
const metaPath = join(vendorDir, "LLAMA_XCFRAMEWORK_SOURCE.json");
const destFramework = join(vendorDir, "llama.xcframework");

function loadMeta() {
  const meta = JSON.parse(readFileSync(metaPath, "utf8"));
  const tag = process.env.LLAMA_XCFRAMEWORK_TAG || meta.tag;
  return { ...meta, tag };
}

function findFramework(dir, depth = 0) {
  if (depth > 4) return null;
  const entries = readdirSync(dir, { withFileTypes: true });
  for (const e of entries) {
    const p = join(dir, e.name);
    if (e.isDirectory() && e.name === "llama.xcframework") return p;
  }
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    if (e.name.startsWith(".") || e.name === "llama.xcframework") continue;
    const found = findFramework(join(dir, e.name), depth + 1);
    if (found) return found;
  }
  return null;
}

async function main() {
  mkdirSync(vendorDir, { recursive: true });
  const meta = loadMeta();

  if (existsSync(destFramework)) {
    console.log(`[llama-xcframework] déjà présent: ${destFramework}`);
    return;
  }

  const url =
    process.env.LLAMA_XCFRAMEWORK_URL ||
    meta.url ||
    `https://github.com/ggml-org/llama.cpp/releases/download/${meta.tag}/llama-${meta.tag}-xcframework.zip`;

  const zipPath = join(vendorDir, `llama-${meta.tag}-xcframework.zip`);
  console.log(`[llama-xcframework] download ${url}`);

  const res = await fetch(url, { redirect: "follow" });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status} for ${url}`);
  }
  await pipeline(res.body, createWriteStream(zipPath));
  console.log(`[llama-xcframework] zip ${(statSync(zipPath).size / 1e6).toFixed(1)} MB`);

  if (process.platform === "win32") {
    execSync(`tar -xf "${zipPath}" -C "${vendorDir}"`, { stdio: "inherit" });
  } else {
    execSync(`unzip -qo "${zipPath}" -d "${vendorDir}"`, { stdio: "inherit" });
  }

  if (!existsSync(destFramework)) {
    const found = findFramework(vendorDir);
    if (found && found !== destFramework) {
      renameSync(found, destFramework);
    }
  }

  if (!existsSync(destFramework)) {
    throw new Error(`llama.xcframework introuvable après extract dans ${vendorDir}`);
  }

  try {
    rmSync(zipPath, { force: true });
  } catch {
    /* ignore */
  }
  console.log(`[llama-xcframework] OK → ${destFramework}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
