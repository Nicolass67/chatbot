#!/usr/bin/env node
/**
 * Fast Simulator orchestrator (Windows → GHA macos-26 → PNG download).
 * Usage: npm.cmd run ios:sim
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolveGhRepo } from "./gh-repo.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..", "..");
const REPO = resolveGhRepo(ROOT);
const WORKFLOW = "iOS Native Fast Simulator";
const ARTIFACT = "simulator-screenshots";

function sh(cmd, args, opts = {}) {
  return spawnSync(cmd, args, { encoding: "utf8", cwd: ROOT, shell: false, ...opts });
}

function shOk(cmd, args, opts = {}) {
  const r = sh(cmd, args, opts);
  if (r.error) throw r.error;
  if (r.status !== 0) {
    throw new Error(((r.stdout || "") + "\n" + (r.stderr || "")).trim() || `${cmd} exit ${r.status}`);
  }
  return r;
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function gitSha() {
  return (shOk("git", ["rev-parse", "HEAD"]).stdout || "").trim();
}

function gitBranch() {
  return (shOk("git", ["rev-parse", "--abbrev-ref", "HEAD"]).stdout || "").trim();
}

function findRunId(sha) {
  const r = shOk("gh", [
    "run", "list", "--repo", REPO, "--workflow", WORKFLOW, "--limit", "15",
    "--json", "databaseId,headSha,status,conclusion,url",
  ]);
  const runs = JSON.parse(r.stdout || "[]");
  const match = runs.find((x) => x.headSha === sha);
  if (!match) throw new Error(`No Fast Simulator run found yet for SHA ${sha}`);
  return match;
}

function downloadArtifact(runId, destDir) {
  fs.mkdirSync(destDir, { recursive: true });
  const tmp = path.join(destDir, "_download");
  fs.rmSync(tmp, { recursive: true, force: true });
  fs.mkdirSync(tmp, { recursive: true });
  shOk("gh", [
    "run",
    "download",
    String(runId),
    "--repo",
    REPO,
    "--name",
    ARTIFACT,
    "--dir",
    tmp,
  ]);
  const walk = (dir) => {
    for (const name of fs.readdirSync(dir)) {
      const p = path.join(dir, name);
      if (fs.statSync(p).isDirectory()) walk(p);
      else if (name.endsWith(".png") || name.endsWith(".json")) fs.copyFileSync(p, path.join(destDir, name));
    }
  };
  walk(tmp);
  fs.rmSync(tmp, { recursive: true, force: true });
}

function main() {
  const t0 = Date.now();
  const sha = gitSha();
  const branch = gitBranch();
  const short = sha.slice(0, 7);
  const outRoot = path.join(ROOT, "artifacts", "ios-simulator");
  const dest = path.join(outRoot, sha);
  if (fs.existsSync(dest)) {
    const bak = `${dest}.prev-${new Date().toISOString().replace(/[:.]/g, "-")}`;
    fs.renameSync(dest, bak);
    console.log(`[SIMULATOR] Preserved previous results → ${bak}`);
  }
  fs.mkdirSync(dest, { recursive: true });

  console.log("FAST SIMULATOR");
  console.log("──────────────");
  console.log(`Branch: ${branch}`);
  console.log(`SHA: ${sha}`);
  console.log(`Artifacts: ${dest}`);
  console.log("");

  const dirty = sh("git", ["status", "--porcelain"]);
  if ((dirty.stdout || "").trim()) {
    console.warn("[SIMULATOR] WARNING: uncommitted changes — GHA runs the pushed commit only.");
  }

  const allowPush = process.env.IOS_SIM_ALLOW_PUSH === "1";
  sh("git", ["fetch", "origin", branch, "--quiet"]);
  const remoteHead = (sh("git", ["rev-parse", `origin/${branch}`]).stdout || "").trim();
  const onRemote =
    remoteHead === sha ||
    sh("git", ["merge-base", "--is-ancestor", sha, `origin/${branch}`]).status === 0;
  if (!onRemote) {
    if (!allowPush) {
      console.error(`[SIMULATOR] SHA ${short} is not on origin/${branch}.`);
      console.error("Push manually, or set IOS_SIM_ALLOW_PUSH=1 to allow push.");
      process.exit(2);
    }
    console.log(`[SIMULATOR] SHA ${short} not on origin — pushing ${branch} (IOS_SIM_ALLOW_PUSH=1)…`);
    const push = sh("git", ["push", "-u", "origin", `HEAD:${branch}`], { stdio: "inherit" });
    if (push.status !== 0) {
      throw new Error("Cannot dispatch Simulator: push failed.");
    }
  } else {
    console.log(`[SIMULATOR] SHA ${short} present on origin/${branch}`);
  }

  console.log("[1/4] Dispatch workflow…");
  shOk("gh", ["workflow", "run", WORKFLOW, "--repo", REPO, "--ref", branch]);
  sleep(5000);

  let run = null;
  for (let i = 0; i < 40; i++) {
    try { run = findRunId(sha); break; } catch { sleep(2000); }
  }
  if (!run) {
    console.error("Could not locate dispatched run for current SHA.");
    process.exit(1);
  }
  console.log(`[2/4] Watching run ${run.databaseId}…`);
  console.log(run.url || "");
  const watch = sh("gh", ["run", "watch", String(run.databaseId), "--repo", REPO, "--exit-status"], { stdio: "inherit" });
  const watchMs = Date.now() - t0;
  if (watch.status !== 0) {
    console.error("\n[SIMULATOR] FAIL — workflow failed");
    process.exit(watch.status || 1);
  }

  console.log("[3/4] Download screenshots…");
  const dl0 = Date.now();
  downloadArtifact(run.databaseId, dest);
  const dlMs = Date.now() - dl0;

  const required = [
    "chat-empty.png",
    "mail-inbox.png",
    "mail-detail-html.png",
    "mail-detail-text.png",
    "mail-summary.png",
    "files-root.png",
    "chat-composer.png",
    "chat-keyboard-dismissed.png",
    "chat-thinking.png",
    "chat-agent.png",
  ];
  console.log("[4/4] Verify PNG…");
  const missing = [];
  for (const f of required) {
    const p = path.join(dest, f);
    if (fs.existsSync(p)) console.log(`  PASS ${f} (${fs.statSync(p).size} bytes)`);
    else { console.log(`  FAIL missing ${f}`); missing.push(f); }
  }

  const latest = path.join(outRoot, "latest");
  fs.rmSync(latest, { recursive: true, force: true });
  fs.mkdirSync(latest, { recursive: true });
  for (const name of fs.readdirSync(dest)) {
    fs.copyFileSync(path.join(dest, name), path.join(latest, name));
  }

  console.log("");
  console.log(`SIMULATOR: ${missing.length ? "FAIL" : "PASS"}`);
  console.log(`SHA: ${short}`);
  console.log(`Watch+CI: ~${Math.round(watchMs / 1000)}s`);
  console.log(`Download: ~${Math.round(dlMs / 1000)}s`);
  console.log(`Total: ~${Math.round((Date.now() - t0) / 1000)}s`);
  console.log(`Dir: ${dest}`);
  if (missing.length) process.exit(1);
}

main();
