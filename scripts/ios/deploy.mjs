/**
 * Fast QA deploy: trigger ios-native-qa.yml → watch SHA-bound run →
 * download artifact → verify qa-meta.json → install → launch → smoke screenshot.
 *
 * Usage:
 *   node scripts/ios/deploy.mjs fast-build [--sha <sha>] [--ref <branch>]
 *   node scripts/ios/deploy.mjs download [--sha <sha>] [--run <id>]
 *   node scripts/ios/deploy.mjs install [path/to.ipa]
 *   node scripts/ios/deploy.mjs deploy [--sha <sha>] [--skip-build] [--no-launch]
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { installIpa } from "./install.mjs";
import { resolveGhRepo } from "./gh-repo.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "../..");
const repo = resolveGhRepo(root);
const workflowFile = "ios-native-qa.yml";
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
  };
  for (let i = 1; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--sha" && argv[i + 1]) out.sha = argv[++i];
    else if (a === "--ref" && argv[i + 1]) out.ref = argv[++i];
    else if (a === "--run" && argv[i + 1]) out.runId = argv[++i];
    else if (a === "--skip-build") out.skipBuild = true;
    else if (a === "--no-launch") out.noLaunch = true;
    else if (a === "--force") out.force = true;
    else if (!a.startsWith("-") && !out.ipa) out.ipa = a;
  }
  return out;
}

function gitSha() {
  return sh("git", ["rev-parse", "HEAD"]).stdout.trim();
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

function findRunForSha(sha, { preferInProgress = true } = {}) {
  const json = sh("gh", [
    "run",
    "list",
    "--repo",
    repo,
    "--workflow",
    workflowFile,
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
    const active = runs.find((r) => r.status === "queued" || r.status === "in_progress" || r.status === "waiting");
    if (active) return active;
  }
  const ok = runs.find((r) => r.status === "completed" && r.conclusion === "success");
  if (ok) return ok;
  return runs[0];
}

function triggerWorkflow(ref) {
  console.log(`[ios:deploy] workflow_dispatch ${workflowFile} --ref ${ref}`);
  sh("gh", ["workflow", "run", workflowFile, "--repo", repo, "--ref", ref]);
}

function watchRun(runId) {
  console.log(`[ios:deploy] watch run ${runId}`);
  shInherit("gh", ["run", "watch", String(runId), "--repo", repo, "--exit-status"]);
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
  console.log(`[ios:deploy] IPA → ${ipaPath}`);
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
  if (meta.workflow && meta.workflow !== "qa") {
    issues.push(`workflow != qa (${meta.workflow})`);
  }
  if (issues.length) {
    throw new Error(`REFUSE install — qa-meta.json invalide:\n- ${issues.join("\n- ")}`);
  }
  console.log(
    `[ios:deploy] meta OK sha=${meta.git_sha.slice(0, 7)} build=${meta.build} bundle=${meta.bundle_id} run=${meta.run_id}`
  );
  return meta;
}

async function cmdFastBuild({ sha, ref, force = false }) {
  ensureGh();
  const expectSha = sha || gitSha();
  const branch = ref || gitBranch();
  console.log(`[ios:deploy] Fast QA for SHA ${expectSha} (ref ${branch})${force ? " [force]" : ""}`);

  let run = force ? null : findRunForSha(expectSha);
  if (force || !run || (run.status === "completed" && run.conclusion !== "success")) {
    triggerWorkflow(branch);
    for (let i = 0; i < 45; i++) {
      sleep(2000);
      const json = sh("gh", [
        "run",
        "list",
        "--repo",
        repo,
        "--workflow",
        workflowFile,
        "--commit",
        expectSha,
        "--limit",
        "5",
        "--json",
        "databaseId,status,conclusion,headSha,url,createdAt",
      ]).stdout;
      const runs = JSON.parse(json || "[]");
      if (!runs.length) continue;
      if (force) {
        const active = runs.find((r) => r.status === "queued" || r.status === "in_progress" || r.status === "waiting");
        run = active || runs[0];
        if (active) break;
        // if newest already completed very recently after our trigger, use it once status settled
        if (runs[0].status === "completed") {
          run = runs[0];
          break;
        }
      } else {
        run = findRunForSha(expectSha);
        if (run) break;
      }
    }
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

async function cmdDownload({ sha, runId }) {
  ensureGh();
  const expectSha = sha || gitSha();
  let id = runId;
  if (!id) {
    const run = findRunForSha(expectSha, { preferInProgress: false });
    if (!run || run.conclusion !== "success") {
      throw new Error(`Pas de run succès pour ${expectSha}`);
    }
    id = String(run.databaseId);
  }
  downloadArtifact(id);
  return verifyMeta(expectSha);
}

async function cmdInstall(ipa) {
  const target = ipa || ipaPath;
  if (!fs.existsSync(target)) throw new Error(`IPA introuvable: ${target}`);
  if (fs.existsSync(metaPath)) {
    // soft check if present
    try {
      verifyMeta(gitSha());
    } catch (e) {
      console.warn(`[ios:deploy] warning meta: ${e.message}`);
    }
  }
  return installIpa(target);
}

async function cmdDeploy(opts) {
  let buildResult = null;
  if (!opts.skipBuild) {
    buildResult = await cmdFastBuild(opts);
  } else {
    if (!fs.existsSync(ipaPath) || !fs.existsSync(metaPath)) {
      await cmdDownload(opts);
    } else {
      verifyMeta(opts.sha || gitSha());
    }
  }

  const installResult = await cmdInstall(opts.ipa || ipaPath);
  if (installResult.code !== 0 && installResult.code !== 2) {
    throw new Error(installResult.message || "install failed");
  }

  if (opts.noLaunch) {
    return { code: installResult.code, build: buildResult, install: installResult };
  }

  // Même si install = HUMAN_REQUIRED, tenter launch/screenshot (app déjà présente).
  if (installResult.code === 2 || installResult.humanRequired) {
    console.error("[ios:deploy] INSTALL_HUMAN_REQUIRED — tentative launch/screenshot si app déjà installée");
  }

  console.log("[ios:deploy] launch + smoke screenshot");
  const qa = path.join(root, "scripts", "ios", "qa.mjs");
  try {
    shInherit("node", [qa, "mount"]);
    shInherit("node", [qa, "launch"]);
    sleep(2500);
    shInherit("node", [qa, "screenshot", "deploy-smoke"]);
  } catch (e) {
    if (installResult.code === 2) {
      console.error(`[ios:deploy] launch/screenshot après HUMAN_REQUIRED: ${e.message}`);
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
  console.log("[ios:deploy] DONE — artifacts/ios/latest.png");
  return {
    code: installResult.code === 2 ? 2 : 0,
    humanRequired: installResult.code === 2,
    build: buildResult,
    install: installResult,
    screenshot: "deploy-smoke",
  };
}

function usage() {
  console.log(`Usage:
  node scripts/ios/deploy.mjs fast-build [--sha SHA] [--ref branch] [--force]
  node scripts/ios/deploy.mjs download [--sha SHA] [--run id]
  node scripts/ios/deploy.mjs install [ipa]
  node scripts/ios/deploy.mjs deploy [--sha SHA] [--skip-build] [--no-launch] [--force]
`);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  try {
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
    if (opts.cmd === "install") {
      const r = await cmdInstall(opts.ipa);
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
