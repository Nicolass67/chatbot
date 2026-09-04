/**
 * Prépare le déploiement IPA iOS (automatisable) jusqu’à iloader.
 *
 * Ce script NE peut PAS installer tout seul sur l’iPhone : iloader n’a pas de CLI
 * publique, et la signature Apple ID / 2FA restent interactives.
 *
 * Automatise :
 * 1. (optionnel) déclenche le workflow GitHub Actions iOS
 * 2. attend le dernier run réussi
 * 3. télécharge Chatbot-unsigned.ipa
 * 4. lance iloader + ouvre l’explorateur sur le fichier
 *
 * Usage :
 *   node scripts/ios-deploy-prep.mjs
 *   node scripts/ios-deploy-prep.mjs --trigger
 *   node scripts/ios-deploy-prep.mjs --run <runId>
 */
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolveGhRepo } from "./ios/gh-repo.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const outDir = path.join(root, "sidestore-prep", "ipa");
const ipaPath = path.join(outDir, "Chatbot-unsigned.ipa");
const workflow = "iOS IPA (unsigned)";
const repo = resolveGhRepo(root);

function sh(cmd, args) {
  const r = spawnSync(cmd, args, {
    encoding: "utf8",
    shell: false,
  });
  if (r.status !== 0) {
    const err = (r.stderr || r.stdout || `exit ${r.status}`).toString();
    throw new Error(err.trim() || `${cmd} failed`);
  }
  return (r.stdout || "").toString().trim();
}

function shInherit(cmd, args) {
  const r = spawnSync(cmd, args, {
    stdio: "inherit",
    shell: false,
  });
  if (r.status !== 0) {
    throw new Error(`${cmd} ${args.join(" ")} failed (exit ${r.status})`);
  }
}

function parseArgs(argv) {
  const out = { trigger: false, runId: null };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--trigger") out.trigger = true;
    if (argv[i] === "--run" && argv[i + 1]) {
      out.runId = argv[++i];
    }
  }
  return out;
}

function ensureGh() {
  try {
    sh("gh", ["--version"]);
  } catch {
    throw new Error("GitHub CLI (gh) requis et authentifié.");
  }
}

function latestSuccessRunId() {
  const json = sh("gh", [
    "run",
    "list",
    "--repo",
    repo,
    "--workflow",
    workflow,
    "--limit",
    "10",
    "--json",
    "databaseId,conclusion,status,headSha,displayTitle,url",
  ]);
  const runs = JSON.parse(json);
  const ok = runs.find(
    (r) => r.conclusion === "success" && r.status === "completed"
  );
  if (!ok) throw new Error("Aucun run iOS IPA réussi trouvé.");
  return String(ok.databaseId);
}

function triggerAndWait() {
  console.log("[ios-deploy] Déclenchement workflow…");
  sh("gh", ["workflow", "run", workflow, "--repo", repo, "--ref", "main"]);
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 8000);
  const json = sh("gh", [
    "run",
    "list",
    "--repo",
    repo,
    "--workflow",
    workflow,
    "--limit",
    "1",
    "--json",
    "databaseId,status",
  ]);
  const runId = String(JSON.parse(json)[0].databaseId);
  console.log(`[ios-deploy] Attente run ${runId}…`);
  shInherit("gh", ["run", "watch", runId, "--repo", repo, "--exit-status"]);
  return runId;
}

function downloadIpa(runId) {
  fs.mkdirSync(outDir, { recursive: true });
  for (const name of fs.readdirSync(outDir)) {
    fs.rmSync(path.join(outDir, name), { force: true, recursive: true });
  }
  console.log(`[ios-deploy] Téléchargement artifact run ${runId}…`);
  shInherit("gh", [
    "run",
    "download",
    runId,
    "--repo",
    repo,
    "-n",
    "chatbot-ios-unsigned",
    "-D",
    outDir,
  ]);
  if (!fs.existsSync(ipaPath)) {
    throw new Error(`IPA introuvable après download: ${ipaPath}`);
  }
  const st = fs.statSync(ipaPath);
  console.log(`[ios-deploy] OK ${ipaPath} (${st.size} octets)`);
}

function launchIloader() {
  const exe = "C:\\Program Files\\iloader\\iloader.exe";
  if (!fs.existsSync(exe)) {
    console.warn(
      "[ios-deploy] iloader.exe introuvable — installe nabdev.iloader"
    );
    return;
  }
  spawn(exe, [], { detached: true, stdio: "ignore" }).unref();
  spawn("explorer.exe", ["/select,", ipaPath], {
    detached: true,
    stdio: "ignore",
  }).unref();
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  ensureGh();

  let runId = args.runId;
  if (args.trigger) {
    runId = triggerAndWait();
  } else if (!runId) {
    runId = latestSuccessRunId();
    console.log(`[ios-deploy] Dernier run réussi: ${runId}`);
  }

  downloadIpa(runId);
  launchIloader();

  console.log(`
[ios-deploy] Prêt.

Action restante (toi, ~15 s) — iloader n’a PAS de CLI d’install :
  1. iPhone déverrouillé + USB
  2. Dans iloader : sélectionne l’appareil
  3. Import IPA → choisis :
     ${ipaPath}

Rappel : les changements Next.js / chat / API N’ONT PAS besoin d’une nouvelle IPA.
Seuls capacitor.config / ios / plugins exigent ce flux.
`);
}

try {
  main();
} catch (err) {
  console.error(
    "[ios-deploy] Échec:",
    err instanceof Error ? err.message : err
  );
  process.exit(1);
}
