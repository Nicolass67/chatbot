#!/usr/bin/env node
/**
 * Chatbot Native — QA iOS (Windows host + iPhone USB + CI Simulator).
 *
 * PHYSICAL DEVICE  → pymobiledevice3 (screenshot/launch/HID si OS l'autorise)
 * SIMULATOR        → GHA XCUITest (pas de Mac local)
 *
 * Ne jamais inventer un PASS HID : si iOS < 27, renvoyer BLOCKED_BY_OS.
 *
 * Usage: node scripts/ios/qa.mjs <command> [args]
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { resolveGhRepo } from "./gh-repo.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..", "..");
const ARTIFACTS = path.join(ROOT, "artifacts", "ios");
const BEFORE = path.join(ARTIFACTS, "before");
const AFTER = path.join(ARTIFACTS, "after");
const BUNDLE_PREFIX = "fr.nicolazer.chatbot.native";
const NATIVE_WORKFLOW = "iOS Native Fast Simulator";
const REPO = resolveGhRepo(ROOT);
const FULL_CI_WORKFLOW = "iOS Native Full CI";

const PY_CANDIDATES = [
  process.env.PYTHON_IOS_QA,
  process.env.LOCALAPPDATA
    ? path.join(process.env.LOCALAPPDATA, "Programs", "Python", "Python312", "python.exe")
    : null,
  "py",
  "python3",
  "python",
].filter(Boolean);

function findPython() {
  for (const c of PY_CANDIDATES) {
    const args =
      c === "py"
        ? ["-3", "-c", "import pymobiledevice3; print('ok')"]
        : ["-c", "import pymobiledevice3; print('ok')"];
    const r = spawnSync(c, args, { encoding: "utf8", shell: false });
    if (r.status === 0 && (r.stdout || "").includes("ok")) {
      return { bin: c, prefix: c === "py" ? ["-3"] : [] };
    }
  }
  throw new Error(
    "Python + pymobiledevice3 introuvables. Installe: pip install -r requirements-ios-qa.txt"
  );
}

function sh(cmd, args, opts = {}) {
  const r = spawnSync(cmd, args, {
    encoding: "utf8",
    shell: false,
    cwd: opts.cwd || ROOT,
  });
  if (opts.allowFail) return r;
  if (r.status !== 0) {
    const err = (r.stderr || r.stdout || `exit ${r.status}`).toString().trim();
    throw new Error(err || `${cmd} failed`);
  }
  return r;
}

function shInherit(cmd, args) {
  const r = spawnSync(cmd, args, { stdio: "inherit", shell: false, cwd: ROOT });
  if (r.status !== 0) throw new Error(`${cmd} failed (${r.status})`);
}

function pyMod(py, moduleArgs, opts = {}) {
  const args = [...py.prefix, "-m", "pymobiledevice3", ...moduleArgs];
  const r = spawnSync(py.bin, args, {
    encoding: "utf8",
    shell: false,
    cwd: ROOT,
  });
  if (opts.allowFail) return r;
  if (r.status !== 0) {
    const err = (r.stderr || r.stdout || "").toString().trim();
    throw new Error(err || `pymobiledevice3 failed`);
  }
  return r;
}

function ensureArtifacts() {
  fs.mkdirSync(ARTIFACTS, { recursive: true });
  fs.mkdirSync(BEFORE, { recursive: true });
  fs.mkdirSync(AFTER, { recursive: true });
}

function stamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`;
}

function safeLabel(label) {
  return String(label || "screen").replace(/[^\w.-]+/g, "_");
}

function listDevices(py) {
  const r = pyMod(py, ["usbmux", "list"], { allowFail: true });
  if (r.status !== 0) return [];
  try {
    return JSON.parse(r.stdout || "[]");
  } catch {
    return [];
  }
}

function primaryDevice(py) {
  const devices = listDevices(py);
  if (!devices.length) throw new Error("Aucun iPhone USB detecte (PHYSICAL DEVICE).");
  return devices[0];
}

function iosMajor(version) {
  const m = String(version || "").match(/^(\d+)/);
  return m ? Number(m[1]) : 0;
}

function resolveBundleId(py) {
  const script = `
import asyncio, json
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.installation_proxy import InstallationProxyService
async def main():
    ld = await create_using_usbmux()
    apps = await InstallationProxyService(lockdown=ld).get_apps()
    hits = [bid for bid in apps if bid.startswith("${BUNDLE_PREFIX}")]
    print(json.dumps(hits))
asyncio.run(main())
`;
  const r = spawnSync(py.bin, [...py.prefix, "-c", script], { encoding: "utf8" });
  if (r.status !== 0) throw new Error((r.stderr || r.stdout || "").toString());
  const hits = JSON.parse(r.stdout || "[]");
  const resigned = hits.find((b) => b !== BUNDLE_PREFIX && b.startsWith(BUNDLE_PREFIX + "."));
  return resigned || hits[0] || null;
}

function classifyHidError(text) {
  const t = String(text || "");
  if (/Remote control requires iOS 27/i.test(t) || /code['\"]?\s*:\s*9021/.test(t)) {
    return {
      status: "BLOCKED_BY_OS",
      detail: "HID media-stream gate: Remote control requires iOS 27.0 or later",
    };
  }
  if (/supportedFeatures["']?\s*:\s*0/.test(t) || /No supported features/i.test(t)) {
    return {
      status: "BLOCKED_BY_OS",
      detail: "get-media-support-info reports supportedFeatures=0",
    };
  }
  if (/Device is not connected/i.test(t)) {
    return { status: "FAIL", detail: "Device not connected" };
  }
  return { status: "FAIL", detail: t.slice(0, 800) };
}

function getMediaSupport(py) {
  const r = pyMod(
    py,
    ["developer", "core-device", "display", "get-media-support-info"],
    { allowFail: true }
  );
  const out = `${r.stdout || ""}\n${r.stderr || ""}`;
  if (r.status !== 0) {
    return { ok: false, raw: out, ...classifyHidError(out) };
  }
  let parsed = null;
  try {
    parsed = JSON.parse(r.stdout || "{}");
  } catch {
    parsed = { raw: r.stdout };
  }
  const features = Number(parsed?.supportedFeatures ?? -1);
  if (features === 0) {
    return {
      ok: false,
      parsed,
      status: "BLOCKED_BY_OS",
      detail: "supportedFeatures=0 (remote control media stream unavailable)",
    };
  }
  return { ok: true, parsed, status: "PASS", detail: `supportedFeatures=${features}` };
}

function cmdCapabilities() {
  console.log(`BACKEND SEPARATION
=================
PHYSICAL DEVICE  — pymobiledevice3 USB (Windows OK)
  screenshot/launch : YES (Developer Mode + DDI)
  HID tap/swipe/type: YES only if iOS >= 27 AND media stream features != 0
  UI tree           : NO without WDA

SIMULATOR        — GHA macos-26 XCUITest (ChatbotNativeUITests)
  full a11y control : YES
  never equals PHYSICAL DEVICE VERIFIED

Current host tooling: see 'versions' command.
`);
}

function cmdVersions(py) {
  const pmd = spawnSync(
    py.bin,
    [...py.prefix, "-c", "import importlib.metadata as m; print(m.version('pymobiledevice3'))"],
    { encoding: "utf8" }
  );
  const mcp = spawnSync(
    py.bin,
    [...py.prefix, "-c", "import importlib.metadata as m; print(m.version('mcp'))"],
    { encoding: "utf8" }
  );
  const node = spawnSync("node", ["-v"], { encoding: "utf8" });
  const npm = spawnSync("npm.cmd", ["-v"], { encoding: "utf8" });
  console.log(
    JSON.stringify(
      {
        backend: "PHYSICAL_OR_SIMULATOR",
        node: (node.stdout || "").trim(),
        npm: (npm.stdout || "").trim(),
        python: py.bin,
        pymobiledevice3: (pmd.stdout || "").trim(),
        mcp: (mcp.stdout || "").trim(),
        artifacts: ARTIFACTS,
      },
      null,
      2
    )
  );
}

function cmdDeviceInfo(py) {
  const devices = listDevices(py);
  if (!devices.length) {
    console.log(
      JSON.stringify(
        {
          backend: "PHYSICAL DEVICE",
          connected: false,
          error: "No USB device",
        },
        null,
        2
      )
    );
    process.exitCode = 1;
    return;
  }
  const d = devices[0];
  let bundleId = null;
  try {
    bundleId = resolveBundleId(py);
  } catch {
    bundleId = null;
  }
  const major = iosMajor(d.ProductVersion);
  console.log(
    JSON.stringify(
      {
        backend: "PHYSICAL DEVICE",
        connected: true,
        name: d.DeviceName,
        productType: d.ProductType,
        ios: d.ProductVersion,
        iosMajor: major,
        build: d.BuildVersion,
        udid: d.UniqueDeviceID || d.Identifier,
        bundleId,
        hidExpected: major >= 27 ? "ATTEMPT" : "BLOCKED_BY_OS",
      },
      null,
      2
    )
  );
}

function cmdMount(py) {
  console.log("[PHYSICAL DEVICE] Montage DDI…");
  pyMod(py, ["mounter", "auto-mount"]);
  console.log("[PHYSICAL DEVICE] DDI PASS");
}

function cmdMediaSupport(py) {
  const info = getMediaSupport(py);
  console.log(JSON.stringify({ backend: "PHYSICAL DEVICE", ...info }, null, 2));
  if (!info.ok) process.exitCode = info.status === "BLOCKED_BY_OS" ? 0 : 1;
  return info;
}

function cmdScreenshot(py, label, slot) {
  ensureArtifacts();
  const safe = safeLabel(label || "screen");
  const ts = stamp();
  const named = path.join(ARTIFACTS, `${safe}.png`);
  const stamped = path.join(ARTIFACTS, `${ts}_${safe}.png`);
  const latest = path.join(ARTIFACTS, "latest.png");
  const labeledLatest = path.join(ARTIFACTS, `latest-${safe}.png`);
  pyMod(py, ["developer", "dvt", "screenshot", stamped]);
  fs.copyFileSync(stamped, named);
  fs.copyFileSync(stamped, latest);
  fs.copyFileSync(stamped, labeledLatest);
  if (slot === "before" || slot === "after") {
    const dir = slot === "before" ? BEFORE : AFTER;
    fs.copyFileSync(stamped, path.join(dir, `${safe}.png`));
  }
  console.log(`[PHYSICAL DEVICE] SCREENSHOT ${named}`);
  console.log(`[PHYSICAL DEVICE] latest → ${latest}`);
  return { named, stamped, latest, labeledLatest };
}

function cmdLaunch(py) {
  const bid = resolveBundleId(py);
  if (!bid) throw new Error("ChatbotNative non installe (SideStore).");
  console.log(`[PHYSICAL DEVICE] Launch ${bid}`);
  pyMod(py, ["developer", "dvt", "launch", bid]);
  console.log("[PHYSICAL DEVICE] Launch PASS — Face ID peut bloquer l'UI.");
  return bid;
}

function normalizeDeepLink(input) {
  let url = String(input || "").trim();
  if (!url) throw new Error("deep link vide");
  if (!url.includes("://")) {
    // Accept qa/mail  OR  mail  OR  tab/mail
    if (url.startsWith("qa/")) url = `chatbot-native://${url}`;
    else if (url.startsWith("tab/") || url.startsWith("assistant/"))
      url = `chatbot-native://qa/${url}`;
    else url = `chatbot-native://qa/${url}`;
  }
  return url;
}

function cmdOpen(py, deeplink) {
  const bid = resolveBundleId(py);
  if (!bid) throw new Error("ChatbotNative non installe.");
  const url = normalizeDeepLink(deeplink);
  console.log(`[PHYSICAL DEVICE] Deep link: ${url}`);
  // pymobiledevice3: `arguments` is ONE shell-string (shlex.split → bundle + argv).
  const launchSpec = `${bid} ${url}`;
  let r = pyMod(py, ["developer", "dvt", "launch", launchSpec], { allowFail: true });
  if (r.status !== 0) {
    console.log("[PHYSICAL DEVICE] launch+url warn:", (r.stderr || r.stdout || "").toString().slice(0, 280));
    r = pyMod(py, ["developer", "dvt", "launch", bid], { allowFail: true });
  }
  // Tab shortcuts via HID when URL argv is ignored (iOS 27+)
  const lower = url.toLowerCase();
  if (lower.includes("/tab/files") || lower.endsWith("://files") || lower.includes("qa/files")) {
    try {
      cmdHidTap(py, 42000, 64000); // Files — right of floating pill tab bar
    } catch (e) {
      console.log("[PHYSICAL DEVICE] HID tab Files:", e.message);
    }
  } else if (lower.includes("/tab/mail") || lower.includes("qa/mail") || lower.includes("://mail")) {
    try {
      cmdHidTap(py, 32768, 64000); // Mail — center of pill
    } catch (e) {
      console.log("[PHYSICAL DEVICE] HID tab Mail:", e.message);
    }
  } else if (lower.includes("/tab/chat") || lower.includes("qa/chat")) {
    try {
      cmdHidTap(py, 24000, 64000); // Chat — left of pill
    } catch (e) {
      console.log("[PHYSICAL DEVICE] HID tab Chat:", e.message);
    }
  }
  console.log("[PHYSICAL DEVICE] Si navigation absente apres unlock: ouvrir manuellement l'URL.");
  return url;
}

function cmdHidTap(py, x, y) {
  console.log(`[PHYSICAL DEVICE] HID tap ${x} ${y}`);
  const r = pyMod(
    py,
    ["developer", "core-device", "universal-hid-service", "tap", "--", String(x), String(y)],
    { allowFail: true }
  );
  const out = `${r.stdout || ""}\n${r.stderr || ""}`;
  if (r.status === 0) {
    console.log("[PHYSICAL DEVICE] HID tap PASS");
    return { status: "PASS" };
  }
  const c = classifyHidError(out);
  console.log(`[PHYSICAL DEVICE] HID tap ${c.status}: ${c.detail}`);
  if (c.status !== "BLOCKED_BY_OS") process.exitCode = 1;
  return c;
}

function cmdHidSwipe(py, x1, y1, x2, y2) {
  console.log(`[PHYSICAL DEVICE] HID drag ${x1},${y1} -> ${x2},${y2}`);
  const r = pyMod(
    py,
    [
      "developer",
      "core-device",
      "universal-hid-service",
      "drag",
      "--",
      String(x1),
      String(y1),
      String(x2),
      String(y2),
    ],
    { allowFail: true }
  );
  const out = `${r.stdout || ""}\n${r.stderr || ""}`;
  if (r.status === 0) {
    console.log("[PHYSICAL DEVICE] HID swipe/drag PASS");
    return { status: "PASS" };
  }
  const c = classifyHidError(out);
  console.log(`[PHYSICAL DEVICE] HID swipe ${c.status}: ${c.detail}`);
  if (c.status !== "BLOCKED_BY_OS") process.exitCode = 1;
  return c;
}

function cmdHidType(py, text) {
  console.log(`[PHYSICAL DEVICE] HID type ${JSON.stringify(text)}`);
  const r = pyMod(
    py,
    ["developer", "core-device", "universal-hid-service", "type", text],
    { allowFail: true }
  );
  const out = `${r.stdout || ""}\n${r.stderr || ""}`;
  if (r.status === 0) {
    console.log("[PHYSICAL DEVICE] HID type PASS");
    return { status: "PASS" };
  }
  const c = classifyHidError(out);
  console.log(`[PHYSICAL DEVICE] HID type ${c.status}: ${c.detail}`);
  if (c.status !== "BLOCKED_BY_OS") process.exitCode = 1;
  return c;
}

function cmdBuild(watch) {
  console.log(`[SIMULATOR/CI] Trigger workflow ${FULL_CI_WORKFLOW} (unit+UI+IPA)`);
  sh("gh", ["workflow", "run", FULL_CI_WORKFLOW, "--repo", REPO]);
  if (!watch) {
    console.log("[SIMULATOR/CI] Triggered. Watch: gh run watch --repo " + REPO);
    return;
  }
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 5000);
  const json = sh("gh", [
    "run",
    "list",
    "--repo",
    REPO,
    "--workflow",
    FULL_CI_WORKFLOW,
    "--limit",
    "1",
    "--json",
    "databaseId",
  ]).stdout;
  const runId = String(JSON.parse(json)[0].databaseId);
  shInherit("gh", ["run", "watch", runId, "--repo", REPO, "--exit-status"]);
}

function cmdInstallPrep(trigger) {
  const args = [path.join(ROOT, "scripts", "ios-deploy-prep.mjs")];
  if (trigger) args.push("--trigger");
  shInherit(process.execPath, args);
}

function cmdTestSim(watch) {
  console.log("[SIMULATOR] Fast Simulator via GHA (prefer: npm.cmd run ios:sim)");
  if (watch) {
    shInherit(process.execPath, [path.join(ROOT, "scripts", "ios", "sim.mjs")]);
    return;
  }
  sh("gh", ["workflow", "run", NATIVE_WORKFLOW, "--repo", REPO]);
  console.log("[SIMULATOR] Triggered. Full wait+download: npm.cmd run ios:sim");
}

function line(status, label, detail = "") {
  const pad = label.padEnd(16);
  return `${pad} ${status}${detail ? `  ${detail}` : ""}`;
}

function cmdAutonomous(py, label) {
  ensureArtifacts();
  const report = {
    backend: "PHYSICAL DEVICE",
    label: label || "autonomous",
    startedAt: new Date().toISOString(),
    checks: {},
  };

  const printHeader = (d) => {
    console.log("");
    console.log("PHYSICAL DEVICE QA");
    console.log("────────────────────────");
    console.log(`Device: ${d?.DeviceName || "?"}`);
    console.log(`iOS: ${d?.ProductVersion || "?"}`);
    console.log("");
  };

  try {
    const devices = listDevices(py);
    report.checks.connection = devices.length
      ? { status: "PASS", devices }
      : { status: "FAIL", detail: "no USB device" };
    if (!devices.length) {
      printHeader(null);
      console.log(line("FAIL", "Connection"));
      report.result = "FAIL";
      throw new Error("No device");
    }
    const d = devices[0];
    printHeader(d);
    console.log(line("PASS", "Connection", d.UniqueDeviceID || d.Identifier));

    try {
      cmdMount(py);
      report.checks.ddi = { status: "PASS" };
      console.log(line("PASS", "DDI"));
    } catch (e) {
      report.checks.ddi = { status: "FAIL", detail: e.message };
      console.log(line("FAIL", "DDI", e.message.slice(0, 80)));
    }

    const media = getMediaSupport(py);
    report.checks.mediaStream = media;
    console.log(line(media.status, "Media stream", media.detail || ""));

    try {
      const bid = cmdLaunch(py);
      report.checks.launch = { status: "PASS", bundleId: bid };
      console.log(line("PASS", "Launch", bid));
    } catch (e) {
      report.checks.launch = { status: "FAIL", detail: e.message };
      console.log(line("FAIL", "Launch", e.message.slice(0, 80)));
    }

    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 2000);

    try {
      const shot = cmdScreenshot(py, label || "autonomous-home", "after");
      report.checks.screenshot = { status: "PASS", ...shot };
      console.log(line("PASS", "Screenshot", shot.named));
    } catch (e) {
      report.checks.screenshot = { status: "FAIL", detail: e.message };
      console.log(line("FAIL", "Screenshot", e.message.slice(0, 80)));
    }

    const tap = cmdHidTap(py, 32768, 32768);
    report.checks.hidTap = tap;
    console.log(line(tap.status, "HID tap", tap.detail || ""));

    const swipe = cmdHidSwipe(py, 32768, 5000, 32768, 60000);
    report.checks.hidSwipe = swipe;
    console.log(line(swipe.status, "HID swipe", swipe.detail || ""));

    const typing = cmdHidType(py, "qa");
    report.checks.hidTyping = typing;
    console.log(line(typing.status, "HID typing", typing.detail || ""));

    const blocked = [tap, swipe, typing].every((x) => x.status === "BLOCKED_BY_OS");
    const anyFail = Object.values(report.checks).some(
      (c) => c && c.status === "FAIL"
    );
    if (anyFail) report.result = "FAIL";
    else if (blocked) report.result = "PARTIAL_NO_HID_OS_GATE";
    else if (
      tap.status === "PASS" &&
      swipe.status === "PASS" &&
      typing.status === "PASS"
    )
      report.result = "PASS_WITH_HID";
    else report.result = "PARTIAL";

    console.log("");
    console.log(`Result: ${report.result}`);
    console.log(`Artifacts: ${ARTIFACTS}`);
  } catch (e) {
    report.result = report.result || "FAIL";
    report.error = e.message;
    console.log(`Result: ${report.result}`);
    if (report.result === "FAIL") process.exitCode = 1;
  }

  report.finishedAt = new Date().toISOString();
  const out = path.join(ARTIFACTS, `qa-report-${stamp()}.json`);
  fs.writeFileSync(out, JSON.stringify(report, null, 2));
  console.log(`Report: ${out}`);
  return report;
}

function cmdQa(py, { device, simulator, label }) {
  if (simulator && !device) {
    console.log("[SIMULATOR] Trigger CI UI tests (not equivalent to PHYSICAL DEVICE)");
    cmdBuild(false);
    return;
  }
  return cmdAutonomous(py, label || "qa-device");
}

function usage() {
  console.log(`Usage: node scripts/ios/qa.mjs <command> [args]

  versions | capabilities | devices | device-info | status
  mount | media-support
  launch | screenshot [label] [--before|--after]
  open <deeplink>          ex: qa/mail | qa/files/documents | qa/assistant/mail
  tap <x> <y>              HID normalised 0..65535
  swipe <x1> <y1> <x2> <y2>
  type <text>
  autonomous [--label name]   campagne PHYSICAL DEVICE complete
  qa --device|--simulator [--label name]
  build [--watch] | install-prep [--trigger] | test-sim [--watch]

Backend labels are always printed as [PHYSICAL DEVICE] or [SIMULATOR].
`);
}

function main() {
  const argv = process.argv.slice(2);
  const cmd = argv[0];
  if (!cmd || cmd === "-h" || cmd === "--help") return usage();

  if (cmd === "capabilities") return cmdCapabilities();
  if (cmd === "build") return cmdBuild(argv.includes("--watch"));
  if (cmd === "install-prep") return cmdInstallPrep(argv.includes("--trigger"));
  if (cmd === "test-sim") return cmdTestSim(argv.includes("--watch"));

  const py = findPython();

  if (cmd === "versions") return cmdVersions(py);
  if (cmd === "devices") {
    console.log(JSON.stringify(listDevices(py), null, 2));
    return;
  }
  if (cmd === "device-info" || cmd === "status") return cmdDeviceInfo(py);
  if (cmd === "mount") return cmdMount(py);
  if (cmd === "media-support") return cmdMediaSupport(py);
  if (cmd === "screenshot") {
    const label = argv.find((a) => !a.startsWith("-") && a !== "screenshot") || "screen";
    const slot = argv.includes("--before") ? "before" : argv.includes("--after") ? "after" : null;
    return cmdScreenshot(py, label, slot);
  }
  if (cmd === "launch") return cmdLaunch(py);
  if (cmd === "open") {
    if (!argv[1]) throw new Error("open <deeplink> requis");
    return cmdOpen(py, argv[1]);
  }
  if (cmd === "tap") {
    if (argv.length < 3) throw new Error("tap <x> <y> requis (0..65535)");
    return cmdHidTap(py, Number(argv[1]), Number(argv[2]));
  }
  if (cmd === "swipe") {
    if (argv.length < 5) throw new Error("swipe <x1> <y1> <x2> <y2> requis");
    return cmdHidSwipe(py, Number(argv[1]), Number(argv[2]), Number(argv[3]), Number(argv[4]));
  }
  if (cmd === "type") {
    if (!argv[1]) throw new Error('type "texte" requis');
    return cmdHidType(py, argv.slice(1).join(" "));
  }
  if (cmd === "autonomous") {
    const i = argv.indexOf("--label");
    return cmdAutonomous(py, i >= 0 ? argv[i + 1] : "autonomous");
  }
  if (cmd === "qa") {
    const i = argv.indexOf("--label");
    return cmdQa(py, {
      device: argv.includes("--device"),
      simulator: argv.includes("--simulator"),
      label: i >= 0 ? argv[i + 1] : null,
    });
  }

  usage();
  process.exit(1);
}

try {
  main();
} catch (err) {
  console.error("[ios-qa] Echec:", err instanceof Error ? err.message : err);
  process.exit(1);
}
