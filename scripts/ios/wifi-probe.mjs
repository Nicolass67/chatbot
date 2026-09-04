/**
 * Probe iPhone reachability over USB / Wi-Fi lockdown (usbmux Network).
 * Never prints pairing secrets or Apple credentials.
 *
 * Usage:
 *   node scripts/ios/wifi-probe.mjs              # discover
 *   node scripts/ios/wifi-probe.mjs enable       # wifi-connections on (needs USB)
 *   node scripts/ios/wifi-probe.mjs status       # wifi-connections get (needs any lockdown)
 */
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "../..");

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
  throw new Error("Python + pymobiledevice3 introuvables");
}

function py(pyInfo, moduleArgs, opts = {}) {
  const r = spawnSync(pyInfo.bin, [...pyInfo.prefix, "-m", "pymobiledevice3", ...moduleArgs], {
    encoding: "utf8",
    shell: false,
    cwd: ROOT,
  });
  if (opts.allowFail) return r;
  if (r.status !== 0) {
    throw new Error((r.stderr || r.stdout || "pymobiledevice3 failed").toString().trim());
  }
  return r;
}

function parseUsbmuxList(stdout) {
  try {
    const data = JSON.parse(stdout || "[]");
    if (Array.isArray(data)) return data;
    if (data && typeof data === "object") return Object.values(data);
  } catch {
    /* ignore */
  }
  return [];
}

function classifyDevices(entries) {
  const usb = [];
  const wifi = [];
  const other = [];
  for (const d of entries) {
    const conn = String(d.ConnectionType || d.connection_type || "").toLowerCase();
    const udid = d.SerialNumber || d.UDID || d.Identifier || d.udid || "?";
    const row = {
      udid,
      connectionType: d.ConnectionType || d.connection_type || "?",
      product: d.ProductType || d.product_type || null,
    };
    if (conn === "usb") usb.push(row);
    else if (conn === "network") wifi.push(row);
    else other.push(row);
  }
  return { usb, wifi, other };
}

function pairingPresent() {
  const dir = path.join(process.env.ProgramData || "C:\\ProgramData", "Apple", "Lockdown");
  if (!fs.existsSync(dir)) return { dir, files: [] };
  const files = fs
    .readdirSync(dir)
    .filter((n) => n.endsWith(".plist") && n !== "SystemConfiguration.plist")
    .map((n) => ({ name: n, udidHint: n.replace(/\.plist$/i, "") }));
  return { dir, files };
}

function pmdVersion(pyInfo) {
  const r = spawnSync(
    pyInfo.bin,
    [
      ...pyInfo.prefix,
      "-c",
      "import importlib.metadata as m; print(m.version('pymobiledevice3'))",
    ],
    { encoding: "utf8", shell: false }
  );
  return (r.stdout || "").trim() || "?";
}

async function cmdDiscover() {
  const pyInfo = findPython();
  const listAll = py(pyInfo, ["usbmux", "list"], { allowFail: true });
  const listUsb = py(pyInfo, ["usbmux", "list", "--usb"], { allowFail: true });
  const listNet = py(pyInfo, ["usbmux", "list", "--network"], { allowFail: true });
  const browse = py(pyInfo, ["remote", "browse"], { allowFail: true });

  let browseJson = { usb: [], wifi: [] };
  try {
    browseJson = JSON.parse(browse.stdout || "{}");
  } catch {
    /* ignore */
  }

  const all = classifyDevices(parseUsbmuxList(listAll.stdout));
  const usbOnly = classifyDevices(parseUsbmuxList(listUsb.stdout));
  const netOnly = classifyDevices(parseUsbmuxList(listNet.stdout));
  const pairing = pairingPresent();

  let wifiConnections = null;
  if (all.usb.length || all.wifi.length) {
    const w = py(pyInfo, ["lockdown", "wifi-connections"], { allowFail: true });
    wifiConnections = {
      ok: w.status === 0,
      stdout: (w.stdout || "").trim().slice(0, 200),
      stderr: (w.stderr || "").trim().slice(0, 200),
    };
  }

  const verdict = {
    usbReady: all.usb.length > 0 || usbOnly.usb.length > 0,
    wifiReady: all.wifi.length > 0 || netOnly.wifi.length > 0,
    pairingRecords: pairing.files.length,
    remoteBrowseWifi: Array.isArray(browseJson.wifi) ? browseJson.wifi.length : 0,
  };

  let recommendation;
  if (verdict.usbReady) {
    recommendation =
      "USB visible — install fiable: npm.cmd run ios:install (défaut auto préfère USB).";
  } else if (verdict.wifiReady) {
    recommendation =
      "Wi-Fi lockdown visible dans usbmux — essaie: npm.cmd run ios:install -- --wifi";
  } else if (verdict.pairingRecords > 0) {
    recommendation =
      "Pairing local OK mais device absent de usbmux. Branche USB une fois, " +
      "`npm.cmd run ios:wifi-probe -- enable`, débranche, déverrouille, même Wi-Fi, re-probe.";
  } else {
    recommendation =
      "Aucun pairing. Branche USB, Trust sur l’iPhone, puis `pymobiledevice3 lockdown pair`.";
  }

  return {
    ok: true,
    pymobiledevice3: pmdVersion(pyInfo),
    usbmux: all,
    usbmuxUsbFlag: usbOnly,
    usbmuxNetworkFlag: netOnly,
    remoteBrowse: {
      usbCount: Array.isArray(browseJson.usb) ? browseJson.usb.length : 0,
      wifiCount: verdict.remoteBrowseWifi,
    },
    pairing: { dir: pairing.dir, count: pairing.files.length, udids: pairing.files.map((f) => f.udidHint) },
    wifiConnections,
    verdict,
    recommendation,
    note:
      "Install IPA unsigned reste via isideload (signature Apple ID). " +
      "Le transport Wi-Fi = usbmux ConnectionType Network, pas un remplacement d’iLoader.",
  };
}

async function cmdEnable() {
  const pyInfo = findPython();
  const list = classifyDevices(parseUsbmuxList(py(pyInfo, ["usbmux", "list", "--usb"], { allowFail: true }).stdout));
  if (!list.usb.length) {
    return {
      ok: false,
      error:
        "USB requis pour activer wifi-connections. Branche l’iPhone, Trust, réessaie.",
    };
  }
  const r = py(pyInfo, ["lockdown", "wifi-connections", "on"], { allowFail: true });
  return {
    ok: r.status === 0,
    stdout: (r.stdout || "").trim(),
    stderr: (r.stderr || "").trim(),
    message:
      r.status === 0
        ? "EnableWifiConnections=on. Débranche, même Wi-Fi, iPhone déverrouillé, puis wifi-probe."
        : "Échec enable — voir stderr.",
  };
}

async function cmdStatus() {
  const pyInfo = findPython();
  const r = py(pyInfo, ["lockdown", "wifi-connections"], { allowFail: true });
  return {
    ok: r.status === 0,
    stdout: (r.stdout || "").trim(),
    stderr: (r.stderr || "").trim(),
  };
}

async function main() {
  const cmd = process.argv[2] || "discover";
  let out;
  if (cmd === "enable") out = await cmdEnable();
  else if (cmd === "status") out = await cmdStatus();
  else out = await cmdDiscover();
  console.log(JSON.stringify(out, null, 2));
  process.exitCode = out.ok === false ? 1 : 0;
}

main().catch((e) => {
  console.error(JSON.stringify({ ok: false, error: e.message }, null, 2));
  process.exit(1);
});
