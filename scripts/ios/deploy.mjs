/**
 * Autonomous iOS deploy orchestrator (Flash IPA → sign → Wi-Fi RSD / USB).
 *
 * Usage:
 *   node scripts/ios/deploy.mjs flash-build [--sha <sha>] [--ref <branch>] [--force]
 *   node scripts/ios/deploy.mjs download [--sha <sha>] [--run <id>]
 *   node scripts/ios/deploy.mjs install [path/to.ipa] [--auto|--usb|--wifi]
 *   node scripts/ios/deploy.mjs deploy [--wifi|--usb|--auto] [--skip-build] [--no-launch]
 *   node scripts/ios/deploy.mjs deploy:wifi | deploy:usb | deploy:auto
 *
 * Default CI for deploy* = ios-native-ipa-flash.yml (Flash IPA only).
 * No screenshots. No Simulator / Contracts / Full CI.
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { installIpa } from "./install.mjs";
import { resolveGhRepo } from "./gh-repo.mjs";
import { ensureDeployVenv } from "./ensure-deploy-venv.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "../..");
const repo = resolveGhRepo(root);
const workflowFile = process.env.IOS_IPA_WORKFLOW || "ios-native-qa.yml";
const flashWorkflowFile = "ios-native-ipa-flash.yml";
const artifactName = "chatbot-ios-native-qa-unsigned";
const expectedBundle = "fr.nicolazer.chatbot.native";
const outDir = path.join(root, "sidestore-prep", "ipa");
const ipaPath = path.join(outDir, "ChatbotNative-unsigned.ipa");
const metaPath = path.join(outDir, "qa-meta.json");

function sh(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, {
    encoding: "utf8",
    shell: false,
    cwd: opts.cwd || root,
    env: { ...process.env, ...(opts.env || {}) },
  });
  if (r.status !== 0 && !opts.allowFail) {
    const err = (r.stderr || r.stdout || `exit ${r.status}`).toString();
    throw new Error(err.trim() || `${cmd} failed`);
  }
  return {
    status: r.status ?? 1,
    stdout: (r.stdout || "").toString(),
    stderr: (r.stderr || "").toString(),
  };
}

function shInherit(cmd, args) {
  const r = spawnSync(cmd, args, { stdio: "inherit", shell: false, cwd: root });
  if (r.status !== 0) {
    throw new Error(`${cmd} ${args.join(" ")} failed (exit ${r.status})`);
  }
}

function parseArgs(argv) {
  const out = {
    cmd: argv[0] || "deploy",
    sha: null,
    ref: null,
    runId: null,
    skipBuild: false,
    noLaunch: false,
    force: false,
    ipa: null,
    /** @type {"auto"|"usb"|"wifi"} */
    transport: "auto",
    baseUrl: null,
  };
  for (let i = 1; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--sha" && argv[i + 1]) out.sha = argv[++i];
    else if (a === "--ref" && argv[i + 1]) out.ref = argv[++i];
    else if (a === "--run" && argv[i + 1]) out.runId = argv[++i];
    else if (a === "--skip-build") out.skipBuild = true;
    else if (a === "--no-launch") out.noLaunch = true;
    else if (a === "--force") out.force = true;
    else if (a === "--wifi") out.transport = "wifi";
    else if (a === "--usb") out.transport = "usb";
    else if (a === "--auto") out.transport = "auto";
    else if (a === "--base-url" && argv[i + 1]) out.baseUrl = argv[++i];
    else if (a === "--transport" && argv[i + 1]) {
      const t = String(argv[++i]).toLowerCase();
      out.transport = t === "network" ? "wifi" : /** @type {"auto"|"usb"|"wifi"} */ (t);
    } else if (!a.startsWith("-") && !out.ipa) out.ipa = a;
  }
  // deploy:wifi / deploy:usb / deploy:auto
  if (out.cmd.startsWith("deploy:")) {
    const t = out.cmd.slice("deploy:".length);
    if (t === "wifi" || t === "usb" || t === "auto") {
      out.transport = t;
      out.cmd = "deploy";
    }
  }
  return out;
}

function gitSha() {
  return sh("git", ["rev-parse", "HEAD"]).stdout.trim();
}

function resolveSha(input) {
  const raw = (input || "").trim();
  if (!raw) return gitSha();
  if (/^[0-9a-f]{40}$/i.test(raw)) return raw.toLowerCase();
  try {
    return sh("git", ["rev-parse", "--verify", raw]).stdout.trim().toLowerCase();
  } catch {
    return raw.toLowerCase();
  }
}

function gitBranch() {
  try {
    return sh("git", ["rev-parse", "--abbrev-ref", "HEAD"]).stdout.trim();
  } catch {
    return "main";
  }
}

function ensureGh() {
  sh("gh", ["--version"]);
}

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function step(n, total, msg) {
  console.log(`[${n}/${total}] ${msg}`);
}

function findRunForSha(sha, { preferInProgress = true, workflow = workflowFile } = {}) {
  const json = sh("gh", [
    "run",
    "list",
    "--repo",
    repo,
    "--workflow",
    workflow,
    "--commit",
    sha,
    "--limit",
    "20",
    "--json",
    "databaseId,status,conclusion,headSha,url,createdAt,event",
  ]).stdout;
  const runs = JSON.parse(json || "[]");
  if (!runs.length) return null;
  if (preferInProgress) {
    const active = runs.find(
      (r) => r.status === "queued" || r.status === "in_progress" || r.status === "waiting"
    );
    if (active) return active;
  }
  const ok = runs.find((r) => r.status === "completed" && r.conclusion === "success");
  if (ok) return ok;
  return runs[0];
}

function triggerWorkflow(ref, { workflow = workflowFile, inputs = {} } = {}) {
  console.log(`[ios:deploy] workflow_dispatch ${workflow} --ref ${ref}`);
  const args = ["workflow", "run", workflow, "--repo", repo, "--ref", ref];
  for (const [k, v] of Object.entries(inputs)) {
    if (v != null && String(v).length) args.push("-f", `${k}=${v}`);
  }
  sh("gh", args);
}

function watchRun(runId) {
  console.log(`[ios:deploy] watch run ${runId}`);
  shInherit("gh", ["run", "watch", String(runId), "--repo", repo, "--exit-status"]);
}

/** Poll for a newly triggered run with exponential backoff (max ~2 min discovery). */
function waitForRunAppear(expectSha, workflow, { maxMs = 120_000 } = {}) {
  let delay = 3000;
  const t0 = Date.now();
  while (Date.now() - t0 < maxMs) {
    const json = sh("gh", [
      "run",
      "list",
      "--repo",
      repo,
      "--workflow",
      workflow,
      "--commit",
      expectSha,
      "--limit",
      "5",
      "--json",
      "databaseId,status,conclusion,headSha,url,createdAt",
    ]).stdout;
    const runs = JSON.parse(json || "[]");
    if (runs.length) {
      const active = runs.find(
        (r) => r.status === "queued" || r.status === "in_progress" || r.status === "waiting"
      );
      return active || runs[0];
    }
    sleep(delay);
    delay = Math.min(delay * 1.5, 15_000);
  }
  return null;
}

function downloadArtifact(runId) {
  fs.mkdirSync(outDir, { recursive: true });
  for (const f of [ipaPath, metaPath]) {
    if (fs.existsSync(f)) fs.unlinkSync(f);
  }
  const tmp = path.join(outDir, `_dl_${runId}`);
  fs.rmSync(tmp, { recursive: true, force: true });
  fs.mkdirSync(tmp, { recursive: true });
  console.log(`[ios:deploy] download artifact ${artifactName} from run ${runId}`);
  shInherit("gh", [
    "run",
    "download",
    String(runId),
    "--repo",
    repo,
    "--name",
    artifactName,
    "--dir",
    tmp,
  ]);
  const walk = (dir) => {
    for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, ent.name);
      if (ent.isDirectory()) walk(p);
      else if (ent.name.endsWith(".ipa")) fs.copyFileSync(p, ipaPath);
      else if (ent.name === "qa-meta.json") fs.copyFileSync(p, metaPath);
    }
  };
  walk(tmp);
  fs.rmSync(tmp, { recursive: true, force: true });
  if (!fs.existsSync(ipaPath)) throw new Error(`IPA manquante après download (${artifactName})`);
  if (!fs.existsSync(metaPath)) throw new Error("qa-meta.json manquant après download");
  const st = fs.statSync(ipaPath);
  if (st.size < 100_000) throw new Error(`IPA trop petite (${st.size} bytes)`);
  console.log(`[ios:deploy] IPA → ${ipaPath} (${st.size} bytes)`);
  console.log(`[ios:deploy] meta → ${metaPath}`);
}

function verifyMeta(expectedSha) {
  const meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
  const issues = [];
  if (!meta.git_sha || meta.git_sha.toLowerCase() !== expectedSha.toLowerCase()) {
    issues.push(`git_sha mismatch: meta=${meta.git_sha} expected=${expectedSha}`);
  }
  if (meta.bundle_id && meta.bundle_id !== expectedBundle) {
    issues.push(`bundle_id mismatch: ${meta.bundle_id} expected ${expectedBundle}`);
  }
  if (meta.workflow && meta.workflow !== "qa" && meta.workflow !== "ipa-flash") {
    issues.push(`workflow invalide (${meta.workflow}) — attendu qa|ipa-flash`);
  }
  const host = String(meta.base_url_host || "").toLowerCase();
  if (!host) {
    issues.push("base_url_host manquant dans qa-meta.json (IPA potentiellement sans origin)");
  } else if (host.includes("your-worker.example")) {
    issues.push(`base_url_host placeholder interdit: ${meta.base_url_host}`);
  }
  if (issues.length) {
    throw new Error(`REFUSE install — qa-meta.json invalide:\n- ${issues.join("\n- ")}`);
  }
  console.log(
    `[ios:deploy] meta OK sha=${meta.git_sha.slice(0, 7)} build=${meta.build} bundle=${meta.bundle_id} host=${meta.base_url_host || "?"} run=${meta.run_id}`
  );
  return meta;
}

async function cmdFlashBuild({ sha, ref, force = false, baseUrl = null }) {
  ensureGh();
  const expectSha = resolveSha(sha);
  const branch = ref || gitBranch();
  const wf = flashWorkflowFile;
  console.log(`[ios:deploy] IPA Flash for SHA ${expectSha} (ref ${branch})${force ? " [force]" : ""}`);

  let run = force ? null : findRunForSha(expectSha, { workflow: wf });
  if (force || !run || (run.status === "completed" && run.conclusion !== "success")) {
    const inputs = {};
    if (baseUrl) inputs.base_url = baseUrl;
    triggerWorkflow(branch, { workflow: wf, inputs });
    run = waitForRunAppear(expectSha, wf);
  }
  if (!run) {
    throw new Error(`Aucun run ${wf} pour commit ${expectSha}.`);
  }
  if (run.status !== "completed") {
    watchRun(run.databaseId);
    run = findRunForSha(expectSha, { preferInProgress: false, workflow: wf });
  }
  if (!run || run.conclusion !== "success") {
    throw new Error(`IPA Flash run échoué pour ${expectSha}: ${run?.url || "no url"}`);
  }
  downloadArtifact(run.databaseId);
  const meta = verifyMeta(expectSha);
  return { runId: String(run.databaseId), meta, ipaPath, metaPath };
}

async function cmdFastBuild({ sha, ref, force = false }) {
  ensureGh();
  const expectSha = resolveSha(sha);
  const branch = ref || gitBranch();
  console.log(`[ios:deploy] Fast QA for SHA ${expectSha} (ref ${branch})${force ? " [force]" : ""}`);

  let run = force ? null : findRunForSha(expectSha);
  if (force || !run || (run.status === "completed" && run.conclusion !== "success")) {
    triggerWorkflow(branch);
    run = waitForRunAppear(expectSha, workflowFile);
  }
  if (!run) {
    throw new Error(
      `Aucun run ios-native-qa.yml pour commit ${expectSha}. ` +
        `Pousse la branche ou vérifie que le workflow existe sur le remote.`
    );
  }
  if (run.status !== "completed") {
    watchRun(run.databaseId);
    run = findRunForSha(expectSha, { preferInProgress: false });
  }
  if (!run || run.conclusion !== "success") {
    throw new Error(`Fast QA run échoué pour ${expectSha}: ${run?.url || "no url"}`);
  }
  downloadArtifact(run.databaseId);
  const meta = verifyMeta(expectSha);
  return { runId: String(run.databaseId), meta, ipaPath, metaPath };
}

async function cmdDownload({ sha, runId, workflow = flashWorkflowFile }) {
  ensureGh();
  const expectSha = resolveSha(sha);
  let id = runId;
  if (!id) {
    let run = findRunForSha(expectSha, { preferInProgress: false, workflow });
    if (!run || run.conclusion !== "success") {
      run = findRunForSha(expectSha, { preferInProgress: false, workflow: workflowFile });
    }
    if (!run || run.conclusion !== "success") {
      throw new Error(`Pas de run succès pour ${expectSha}`);
    }
    id = String(run.databaseId);
  }
  downloadArtifact(id);
  return verifyMeta(expectSha);
}

async function cmdInstall(ipa, transport = "auto", { noLaunch = false } = {}) {
  const target = ipa || ipaPath;
  if (!fs.existsSync(target)) throw new Error(`IPA introuvable: ${target}`);
  if (fs.existsSync(metaPath)) {
    try {
      verifyMeta(gitSha());
    } catch (e) {
      console.warn(`[ios:deploy] warning meta: ${e.message}`);
    }
  }
  return installIpa(target, { transport, noLaunch });
}

/**
 * Autonomous pipeline: Flash IPA → download → sign → Wi-Fi/USB install (+ launch).
 * No screenshots.
 */
async function cmdDeploy(opts) {
  const total = 8;
  let buildResult = null;

  if (!opts.skipBuild) {
    step(1, total, "Waiting for GitHub Flash IPA build");
    buildResult = await cmdFlashBuild(opts);
  } else {
    step(1, total, "Reusing local IPA (skip-build)");
    if (!fs.existsSync(ipaPath) || !fs.existsSync(metaPath)) {
      await cmdDownload(opts);
    } else {
      verifyMeta(resolveSha(opts.sha));
    }
  }

  step(2, total, "IPA downloaded");
  try {
    ensureDeployVenv();
  } catch (e) {
    if (opts.transport === "wifi") throw e;
    console.warn(`[ios:deploy] deploy-venv: ${e.message}`);
  }

  step(3, total, "Signature ready (local Apple credentials)");
  step(4, total, `Finding iPhone (${opts.transport || "auto"})`);
  step(5, total, "Trusted Tunnel / install transport");

  const installResult = await cmdInstall(opts.ipa || ipaPath, opts.transport || "auto", {
    noLaunch: opts.noLaunch,
  });

  if (installResult.code !== 0 && installResult.code !== 2) {
    throw new Error(installResult.message || "install failed");
  }

  if (installResult.backend === "wifi-rsd") {
    step(6, total, "Installing (Wi-Fi RSD) — done");
    if (opts.noLaunch) {
      step(7, total, "Launch skipped (--no-launch)");
      step(8, total, "Deployment successful (install only)");
      return { code: 0, build: buildResult, install: installResult };
    }
    if (installResult.launched) {
      step(7, total, "Launching — done");
      step(8, total, "Deployment successful");
      return { code: 0, build: buildResult, install: installResult };
    }
    step(7, total, "Launch via qa.mjs (Wi-Fi install OK, CoreDevice launch miss)");
    try {
      const qa = path.join(root, "scripts", "ios", "qa.mjs");
      shInherit("node", [qa, "launch"]);
      step(8, total, "Deployment successful");
      return { code: 0, build: buildResult, install: installResult, launch: "qa.mjs" };
    } catch (e) {
      console.warn(`[ios:deploy] launch fallback: ${e.message}`);
      step(8, total, "Install OK — launch failed");
      return {
        code: 0,
        installOk: true,
        launchOk: false,
        build: buildResult,
        install: installResult,
        message: e.message,
      };
    }
  }

  step(6, total, `Installing (${installResult.backend || "usb"})`);
  if (opts.noLaunch) {
    step(7, total, "Launch skipped");
    step(8, total, installResult.code === 0 ? "Deployment successful" : "Install human required");
    return { code: installResult.code, build: buildResult, install: installResult };
  }

  if (installResult.code === 2 || installResult.humanRequired) {
    console.error("[ios:deploy] INSTALL_HUMAN_REQUIRED — tentative launch si app déjà installée");
  }

  step(7, total, "Launching");
  const qa = path.join(root, "scripts", "ios", "qa.mjs");
  try {
    shInherit("node", [qa, "launch"]);
  } catch (e) {
    if (installResult.code === 2) {
      return {
        code: 2,
        humanRequired: true,
        build: buildResult,
        install: installResult,
        phase: "launch",
        message: e.message,
      };
    }
    throw e;
  }
  step(8, total, "Deployment successful");
  return {
    code: installResult.code === 2 ? 2 : 0,
    humanRequired: installResult.code === 2,
    build: buildResult,
    install: installResult,
  };
}

function usage() {
  console.log(`Usage:
  node scripts/ios/deploy.mjs flash-build [--sha SHA] [--ref branch] [--force]
  node scripts/ios/deploy.mjs fast-build [--sha SHA] [--ref branch] [--force]
  node scripts/ios/deploy.mjs download [--sha SHA] [--run id]
  node scripts/ios/deploy.mjs install [ipa] [--auto|--usb|--wifi]
  node scripts/ios/deploy.mjs deploy [--wifi|--usb|--auto] [--skip-build] [--no-launch] [--force]
  node scripts/ios/deploy.mjs deploy:wifi | deploy:usb | deploy:auto

  Transport:
    --wifi  RemotePairing Trusted Tunnel RSD (preferred, no USB)
    --usb   isideload usbmux USB (fallback)
    --auto  Wi-Fi first, then USB
`);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  try {
    if (opts.cmd === "flash-build") {
      const r = await cmdFlashBuild(opts);
      console.log(JSON.stringify({ ok: true, ...r, ipaPath, metaPath }, null, 2));
      return;
    }
    if (opts.cmd === "fast-build") {
      const r = await cmdFastBuild(opts);
      console.log(JSON.stringify({ ok: true, ...r, ipaPath, metaPath }, null, 2));
      return;
    }
    if (opts.cmd === "download") {
      const meta = await cmdDownload(opts);
      console.log(JSON.stringify({ ok: true, meta, ipaPath }, null, 2));
      return;
    }
    if (opts.cmd === "wifi-probe") {
      const probe = path.join(root, "scripts", "ios", "wifi-probe.mjs");
      const sub = opts.ipa || "discover";
      shInherit("node", [probe, sub]);
      return;
    }
    if (opts.cmd === "ensure-venv") {
      const py = ensureDeployVenv({ force: opts.force });
      console.log(JSON.stringify({ ok: true, python: py }));
      return;
    }
    if (opts.cmd === "install") {
      const r = await cmdInstall(opts.ipa, opts.transport || "auto", {
        noLaunch: opts.noLaunch,
      });
      process.exitCode = r.code === 2 ? 2 : r.code === 0 ? 0 : 1;
      console.log(JSON.stringify(r, null, 2));
      return;
    }
    if (opts.cmd === "deploy" || opts.cmd === "run") {
      const r = await cmdDeploy(opts);
      process.exitCode = r.code === 2 ? 2 : r.code === 0 ? 0 : 1;
      console.log(JSON.stringify({ ok: r.code === 0, ...r }, null, 2));
      return;
    }
    usage();
    process.exitCode = 1;
  } catch (e) {
    console.error(`[ios:deploy] FAIL: ${e.message}`);
    process.exitCode = 1;
  }
}

main();
