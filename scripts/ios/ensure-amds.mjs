#!/usr/bin/env node
/**
 * Ensure Apple Mobile Device Support / usbmuxd is reachable on Windows.
 *
 * Store iTunes embeds AMDS (AppleMobileDeviceProcess) but does **not** register a
 * classic Windows service. If iTunes hasn't been launched this session, nothing
 * listens on 127.0.0.1:27015 → pymobiledevice3 / isideload fail with
 * ConnectionFailedToUsbmuxdError even when the iPhone USB device is OK in PnP.
 *
 * Fix: launch Store iTunes (AppsFolder) to wake AMDS, then poll usbmux.
 */
import { spawnSync } from "node:child_process";
import net from "node:net";
import { ensureDeployVenv, venvPythonPath } from "./ensure-deploy-venv.mjs";

const USBMUX_HOST = "127.0.0.1";
const USBMUX_PORT = 27015;

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function tcpOpen(host, port, timeoutMs = 400) {
  return new Promise((resolve) => {
    const sock = net.connect({ host, port });
    const done = (ok) => {
      try {
        sock.destroy();
      } catch {
        /* ignore */
      }
      resolve(ok);
    };
    sock.setTimeout(timeoutMs);
    sock.once("connect", () => done(true));
    sock.once("timeout", () => done(false));
    sock.once("error", () => done(false));
  });
}

function launchStoreItunes() {
  if (process.platform !== "win32") return false;
  // Avoid nested quotes in -Command (PowerShell "terminator missing" on Win FR).
  const ps = [
    "$ErrorActionPreference = 'Stop'",
    "$app = Get-StartApps | Where-Object { $_.Name -match 'iTunes' } | Select-Object -First 1",
    "if (-not $app) { Write-Output 'NO_ITUNES'; exit 2 }",
    "$target = 'shell:AppsFolder\\' + $app.AppID",
    "Start-Process $target",
    "Write-Output ('LAUNCHED:' + $app.AppID)",
  ].join("; ");
  const r = spawnSync(
    "powershell.exe",
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps],
    { encoding: "utf8", windowsHide: true, timeout: 20_000 }
  );
  const out = ((r.stdout || "") + (r.stderr || "")).trim();
  if (r.status === 0 && out.includes("LAUNCHED:")) {
    console.log(`[amds] ${out}`);
    return true;
  }
  console.warn(`[amds] iTunes launch failed: ${out.slice(0, 300) || `exit ${r.status}`}`);
  return false;
}

function listUsbmuxDevices() {
  try {
    ensureDeployVenv();
    const py = venvPythonPath();
    const r = spawnSync(
      py,
      [
        "-c",
        "import asyncio; from pymobiledevice3.usbmux import list_devices; "
          + "devs=asyncio.run(list_devices()); "
          + "print(len(devs)); "
          + "[print(getattr(d,'connection_type',None), getattr(d,'serial',None)) for d in devs]",
      ],
      { encoding: "utf8", windowsHide: true, timeout: 15_000 }
    );
    if (r.status !== 0) return { ok: false, count: 0, detail: (r.stderr || r.stdout || "").trim() };
    const lines = (r.stdout || "").trim().split(/\r?\n/).filter(Boolean);
    const count = Number(lines[0] || 0);
    return { ok: count > 0, count, detail: lines.slice(1).join(" | ") };
  } catch (e) {
    return { ok: false, count: 0, detail: e.message };
  }
}

/**
 * @param {{ timeoutMs?: number, forceLaunch?: boolean }} [opts]
 * @returns {Promise<{ ok: boolean, launched: boolean, detail: string }>}
 */
export async function ensureAppleMobileDeviceSupport(opts = {}) {
  const timeoutMs = opts.timeoutMs ?? 45_000;
  const forceLaunch = Boolean(opts.forceLaunch);

  const listening = await tcpOpen(USBMUX_HOST, USBMUX_PORT);
  if (listening && !forceLaunch) {
    const devices = listUsbmuxDevices();
    if (devices.ok) {
      console.log(`[amds] usbmux OK (:${USBMUX_PORT}) devices=${devices.count} ${devices.detail}`);
      return { ok: true, launched: false, detail: devices.detail };
    }
    console.warn(`[amds] port open but no device yet: ${devices.detail.slice(0, 200)}`);
  } else if (!listening) {
    console.warn(
      `[amds] usbmux not listening on ${USBMUX_HOST}:${USBMUX_PORT} — waking Store iTunes / AMDS`
    );
  }

  const launched = launchStoreItunes();
  const deadline = Date.now() + timeoutMs;
  let lastDetail = "waiting";

  while (Date.now() < deadline) {
    await sleep(1500);
    const up = await tcpOpen(USBMUX_HOST, USBMUX_PORT);
    if (!up) {
      lastDetail = "usbmux still down";
      continue;
    }
    const devices = listUsbmuxDevices();
    lastDetail = devices.detail || `count=${devices.count}`;
    if (devices.ok) {
      console.log(`[amds] usbmux ready devices=${devices.count} ${devices.detail}`);
      return { ok: true, launched, detail: devices.detail };
    }
    // Port up but no device — keep waiting (trust prompt / cable settle).
    console.log(`[amds] usbmux up, waiting for device… (${lastDetail.slice(0, 120)})`);
  }

  return {
    ok: false,
    launched,
    detail:
      `AMDS/usbmux unavailable after ${timeoutMs}ms (${lastDetail}). `
      + `Open iTunes once, unlock iPhone, trust PC.`,
  };
}

if (process.argv[1] && process.argv[1].replace(/\\/g, "/").endsWith("ensure-amds.mjs")) {
  ensureAppleMobileDeviceSupport({ forceLaunch: process.argv.includes("--force") })
    .then((r) => {
      console.log(JSON.stringify(r));
      process.exit(r.ok ? 0 : 1);
    })
    .catch((e) => {
      console.error(e);
      process.exit(1);
    });
}
