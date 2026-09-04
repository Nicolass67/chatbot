#!/usr/bin/env node
/**
 * Ensure local Python 3.13+ venv for Wi-Fi RSD deploy (pymobiledevice3==11.3.1).
 * Path: scripts/ios/.deploy-venv/ (gitignored). Never use global Python 3.12 for TLS-PSK.
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const VENV = path.join(__dirname, ".deploy-venv");
const REQ_PY = [3, 13];
const REQ_PMD = "11.3.1";

function winPythonCandidates() {
  const local = process.env.LOCALAPPDATA || "";
  return [
    process.env.IOS_DEPLOY_PYTHON,
    process.env.PYTHON313,
    path.join(local, "Programs", "Python", "Python313", "python.exe"),
    path.join(local, "Programs", "Python", "Python314", "python.exe"),
    "py",
  ].filter(Boolean);
}

function probePython(cmd, args = ["-c", "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}.{sys.version_info[2]}')"]) {
  const r = spawnSync(cmd, args, { encoding: "utf8", windowsHide: true });
  if (r.status !== 0) return null;
  const ver = (r.stdout || "").trim();
  const m = ver.match(/^(\d+)\.(\d+)\.(\d+)/);
  if (!m) return null;
  return { cmd, version: [Number(m[1]), Number(m[2]), Number(m[3])], raw: ver };
}

function findHostPython313() {
  for (const c of winPythonCandidates()) {
    if (c === "py") {
      const r = probePython("py", [
        "-3.13",
        "-c",
        "import sys; print(f'{sys.version_info[0]}.{sys.version_info[1]}.{sys.version_info[2]}')",
      ]);
      if (
        r &&
        (r.version[0] > REQ_PY[0] ||
          (r.version[0] === REQ_PY[0] && r.version[1] >= REQ_PY[1]))
      ) {
        return { cmd: "py", prefixArgs: ["-3.13"], version: r.version, raw: r.raw };
      }
      continue;
    }
    if (!fs.existsSync(c) && path.isAbsolute(c)) continue;
    const r = probePython(c);
    if (!r) continue;
    if (r.version[0] > REQ_PY[0] || (r.version[0] === REQ_PY[0] && r.version[1] >= REQ_PY[1])) {
      return { cmd: c, prefixArgs: [], version: r.version, raw: r.raw };
    }
  }
  return null;
}

export function venvPythonPath() {
  if (process.platform === "win32") {
    return path.join(VENV, "Scripts", "python.exe");
  }
  return path.join(VENV, "bin", "python");
}

function checkVenvOk(py) {
  const r = spawnSync(
    py,
    [
      "-c",
      [
        "import sys, importlib.metadata as m",
        "assert sys.version_info >= (3,13), sys.version",
        `v=m.version('pymobiledevice3')`,
        `assert v=='${REQ_PMD}', v`,
        "print(sys.version.split()[0], v)",
      ].join("\n"),
    ],
    { encoding: "utf8", windowsHide: true }
  );
  return r.status === 0 ? (r.stdout || "").trim() : null;
}

export function ensureDeployVenv({ force = false } = {}) {
  const pyPath = venvPythonPath();
  if (!force && fs.existsSync(pyPath)) {
    const ok = checkVenvOk(pyPath);
    if (ok) {
      console.log(`[deploy-venv] OK ${ok} (${pyPath})`);
      return pyPath;
    }
  }

  const host = findHostPython313();
  if (!host) {
    throw new Error(
      "Python 3.13+ introuvable. Installe Python 3.13 (TLS-PSK natif requis pour Trusted Tunnel)."
    );
  }
  console.log(`[deploy-venv] host Python ${host.raw} → ${VENV}`);

  fs.rmSync(VENV, { recursive: true, force: true });
  const create = spawnSync(host.cmd, [...host.prefixArgs, "-m", "venv", VENV], {
    encoding: "utf8",
    windowsHide: true,
    stdio: "inherit",
  });
  if (create.status !== 0) throw new Error("venv create failed");

  const pip = spawnSync(
    pyPath,
    ["-m", "pip", "install", "--upgrade", "pip", `pymobiledevice3==${REQ_PMD}`],
    { encoding: "utf8", windowsHide: true, stdio: "inherit" }
  );
  if (pip.status !== 0) throw new Error("pip install pymobiledevice3 failed");

  const ok = checkVenvOk(pyPath);
  if (!ok) throw new Error("venv verification failed after install");
  console.log(`[deploy-venv] ready ${ok}`);
  return pyPath;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const force = process.argv.includes("--force");
    const py = ensureDeployVenv({ force });
    console.log(JSON.stringify({ ok: true, python: py }));
  } catch (e) {
    console.error(`[deploy-venv] FAIL: ${e.message}`);
    process.exit(1);
  }
}
