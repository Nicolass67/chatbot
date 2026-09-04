/**
 * Install IPA on physical iPhone.
 *
 * Transports:
 *   wifi — RemotePairing → Trusted Tunnel → RSD (Python 3.13 + pymobiledevice3)
 *          after local isideload sign (no USB)
 *   usb  — isideload CLI via usbmux USB (historical path)
 *   auto — wifi first, then usb fallback
 *
 * Credentials (never git):
 *   APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD (or APPLE_PASSWORD)
 *   or Windows Credential Manager target "ChatbotAppleID"
 */
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { ensureDeployVenv, venvPythonPath } from "./ensure-deploy-venv.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "../..");
const CRED_TARGET = "ChatbotAppleID";
const SIGNED_DIR = path.join(root, "sidestore-prep", "signed-app");
const WIFI_SCRIPT = path.join(__dirname, "wifi_rsd_deploy.py");

const ILOADER_CANDIDATES = [
  process.env.ILOADER_PATH,
  "C:\\Program Files\\iloader\\iloader.exe",
  "C:\\Program Files (x86)\\iloader\\iloader.exe",
  path.join(process.env.LOCALAPPDATA || "", "Programs", "iloader", "iloader.exe"),
].filter(Boolean);

const CLI_CANDIDATES = [
  process.env.ISIDELOAD_CLI,
  path.join(__dirname, "tools", "isideload-cli", "target", "release", "chatbot-isideload-cli.exe"),
  path.join(__dirname, "tools", "isideload-cli", "target", "release", "chatbot-isideload-cli"),
  path.join(__dirname, "tools", "bin", "chatbot-isideload-cli.exe"),
  path.join(__dirname, "tools", "bin", "chatbot-isideload-cli"),
].filter(Boolean);

function findCli() {
  for (const p of CLI_CANDIDATES) {
    if (p && fs.existsSync(p)) return p;
  }
  return null;
}

function findIloader() {
  for (const p of ILOADER_CANDIDATES) {
    if (p && fs.existsSync(p)) return p;
  }
  return null;
}

/** Read Apple ID + password from env or Windows Credential Manager. */
export function resolveAppleCredentials() {
  const envId = process.env.APPLE_ID?.trim();
  const envPass =
    process.env.APPLE_APP_SPECIFIC_PASSWORD?.trim() ||
    process.env.APPLE_PASSWORD?.trim();
  if (envId && envPass) {
    return { appleId: envId, password: envPass, source: "env" };
  }

  if (process.platform === "win32") {
    try {
      const ps = `
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
try {
  $c = Get-StoredCredential -Target '${CRED_TARGET}' -ErrorAction Stop
  if ($c) {
    $pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
      [Runtime.InteropServices.Marshal]::SecureStringToBSTR($c.Password)
    )
    Write-Output ($c.UserName + [char]9 + $pass)
    exit 0
  }
} catch {}
$code = @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class CredReadHelper {
  [DllImport("advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);
  [DllImport("advapi32.dll", SetLastError=true)]
  public static extern bool CredFree(IntPtr cred);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist;
    public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName;
  }
  public static string Read(string target) {
    IntPtr p;
    if (!CredRead(target, 1, 0, out p)) return null;
    var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
    string pass = c.CredentialBlobSize > 0
      ? Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2)
      : "";
    string user = c.UserName ?? "";
    CredFree(p);
    return user + "\\t" + pass;
  }
}
"@
Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue
$line = [CredReadHelper]::Read('${CRED_TARGET}')
if ($line) { Write-Output $line; exit 0 }
exit 1
`;
      const r = spawnSync("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps], {
        encoding: "utf8",
        windowsHide: true,
      });
      const line = (r.stdout || "").trim();
      if (r.status === 0 && line.includes("\t")) {
        const [appleId, password] = line.split("\t");
        if (appleId && password) {
          return { appleId, password, source: "credential-manager" };
        }
      }
    } catch {
      /* ignore */
    }
  }
  return null;
}

function openIloaderFallback(ipaPath) {
  const iloader = findIloader();
  const abs = path.resolve(ipaPath);
  if (process.platform === "win32") {
    spawnSync("explorer.exe", ["/select,", abs], { shell: false });
  }
  if (iloader) {
    spawn(iloader, [], { detached: true, stdio: "ignore" }).unref();
    return {
      code: 2,
      humanRequired: true,
      message: `INSTALL_HUMAN_REQUIRED — iLoader ouvert. Importe ${abs} (Apple ID). Puis: npm.cmd run ios:launch`,
      backend: "iloader-gui",
      ipa: abs,
    };
  }
  return {
    code: 2,
    humanRequired: true,
    message: `INSTALL_HUMAN_REQUIRED — iLoader introuvable. Installe manuellement: ${abs}`,
    backend: "manual",
    ipa: abs,
  };
}

function credEnv(creds) {
  return {
    ...process.env,
    APPLE_ID: creds.appleId,
    APPLE_APP_SPECIFIC_PASSWORD: creds.password,
    APPLE_PASSWORD: creds.password,
  };
}

const READ_INFO_PY = path.join(__dirname, "read_bundle_info.py");

/** Read CFBundle* from .ipa or .app via deploy-venv Python. */
export function readBundleInfo(targetPath) {
  ensureDeployVenv();
  const py = venvPythonPath();
  const r = spawnSync(py, [READ_INFO_PY, path.resolve(targetPath)], {
    encoding: "utf8",
    windowsHide: true,
  });
  if (r.status !== 0) {
    throw new Error((r.stderr || r.stdout || "read_bundle_info failed").toString().trim());
  }
  return JSON.parse((r.stdout || "").trim());
}

function wipeSignedDir(outDir) {
  fs.mkdirSync(outDir, { recursive: true });
  for (const name of fs.readdirSync(outDir)) {
    fs.rmSync(path.join(outDir, name), { recursive: true, force: true });
  }
}

/**
 * Sign IPA locally (no device). Returns path to signed .app directory.
 * Never reuses a pre-existing signed .app — stale fallback is forbidden.
 */
export function signIpa(ipaPath, { outDir = SIGNED_DIR, expect } = {}) {
  const abs = path.resolve(ipaPath);
  const cli = findCli();
  const creds = resolveAppleCredentials();
  if (!cli) {
    return { code: 1, message: "isideload CLI introuvable (cargo build --release)", backend: "none" };
  }
  if (!creds) {
    return {
      code: 2,
      humanRequired: true,
      message: `Pas de credentials (vault ${CRED_TARGET} ou APPLE_ID)`,
      backend: "none",
    };
  }

  let ipaInfo;
  try {
    ipaInfo = readBundleInfo(abs);
  } catch (e) {
    return { code: 1, message: `IPA Info.plist unreadable: ${e.message}`, backend: "none" };
  }
  if (expect?.version && String(ipaInfo.version) !== String(expect.version)) {
    return {
      code: 1,
      message: `IPA version mismatch: ipa=${ipaInfo.version} expected=${expect.version}`,
      backend: "none",
      ipaInfo,
    };
  }
  if (expect?.build && String(ipaInfo.build) !== String(expect.build)) {
    return {
      code: 1,
      message: `IPA build mismatch: ipa=${ipaInfo.build} expected=${expect.build}`,
      backend: "none",
      ipaInfo,
    };
  }

  // Wipe prior signed output so a failed sign cannot leave an older .app to reuse.
  wipeSignedDir(outDir);
  console.log(
    `[ios:install] sign via isideload (${creds.source}) — source ${ipaInfo.version}/${ipaInfo.build}`
  );
  const r = spawnSync(cli, ["sign", "--out", outDir, abs], {
    encoding: "utf8",
    env: credEnv(creds),
    windowsHide: true,
    timeout: 10 * 60 * 1000,
  });
  const out = ((r.stdout || "") + (r.stderr || "")).trim();
  const lines = (r.stdout || "")
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);
  const signedPath = lines.reverse().find((l) => l.endsWith(".app") && fs.existsSync(l));
  if (r.status === 0 && signedPath) {
    let signedInfo;
    try {
      signedInfo = readBundleInfo(signedPath);
    } catch (e) {
      wipeSignedDir(outDir);
      return {
        code: 1,
        message: `signed .app unreadable: ${e.message}`,
        backend: "isideload-sign",
        ipaInfo,
      };
    }
    // Free provisioning may suffix team id on bundle id — compare version/build only.
    if (String(signedInfo.version) !== String(ipaInfo.version) || String(signedInfo.build) !== String(ipaInfo.build)) {
      wipeSignedDir(outDir);
      return {
        code: 1,
        message:
          `REFUSE stale/mismatched signed .app: signed=${signedInfo.version}/${signedInfo.build} ` +
          `ipa=${ipaInfo.version}/${ipaInfo.build}`,
        backend: "isideload-sign",
        ipaInfo,
        signedInfo,
      };
    }
    return {
      code: 0,
      message: "signed",
      backend: "isideload-sign",
      signedApp: signedPath,
      ipaInfo,
      signedInfo,
    };
  }
  wipeSignedDir(outDir);
  if (r.status === 2 || /HUMAN_REQUIRED|2FA/i.test(out)) {
    return {
      code: 2,
      humanRequired: true,
      message: "HUMAN_REQUIRED during sign (2FA) — no stale signed-app fallback",
      backend: "isideload-sign",
      detail: out.slice(0, 400),
      ipaInfo,
    };
  }
  return {
    code: 1,
    message: `sign failed (exit ${r.status}) — no stale signed-app fallback`,
    backend: "isideload-sign",
    detail: out.slice(0, 500),
    ipaInfo,
  };
}

function runWifiRsd(signedApp, { noLaunch = false, expectVersion = null, expectBuild = null } = {}) {
  ensureDeployVenv();
  const py = venvPythonPath();
  const args = [WIFI_SCRIPT, signedApp, "--retries", "3"];
  if (noLaunch) args.push("--no-launch");
  if (expectVersion) args.push("--expect-version", String(expectVersion));
  if (expectBuild) args.push("--expect-build", String(expectBuild));
  console.log(`[ios:install] Wi-Fi RSD via ${py}`);
  const r = spawnSync(py, args, {
    encoding: "utf8",
    windowsHide: true,
    timeout: 8 * 60 * 1000,
    env: {
      ...process.env,
      ...(noLaunch ? { IOS_NO_LAUNCH: "1" } : {}),
      ...(expectVersion ? { IOS_EXPECT_VERSION: String(expectVersion) } : {}),
      ...(expectBuild ? { IOS_EXPECT_BUILD: String(expectBuild) } : {}),
    },
  });
  const combined = ((r.stdout || "") + "\n" + (r.stderr || "")).trim();
  let json = null;
  for (const line of (r.stdout || "").split(/\r?\n/).reverse()) {
    const t = line.trim();
    if (t.startsWith("{") && t.includes("ok")) {
      try {
        json = JSON.parse(t);
        break;
      } catch {
        /* continue */
      }
    }
  }
  if (r.status === 0 && json?.ok) {
    if (expectVersion && String(json.version) !== String(expectVersion)) {
      return {
        code: 1,
        message: `post-install version mismatch device=${json.version} expected=${expectVersion}`,
        backend: "wifi-rsd",
        transport: "wifi",
        detail: json,
      };
    }
    if (expectBuild && String(json.build) !== String(expectBuild)) {
      return {
        code: 1,
        message: `post-install build mismatch device=${json.build} expected=${expectBuild}`,
        backend: "wifi-rsd",
        transport: "wifi",
        detail: json,
      };
    }
    return {
      code: 0,
      message: "installed via wifi-rsd",
      backend: "wifi-rsd",
      transport: "wifi",
      launched: Boolean(json.launched),
      bundleId: json.bundle_id,
      version: json.version,
      build: json.build,
      detail: json,
    };
  }
  return {
    code: 1,
    message: `wifi-rsd failed (exit ${r.status})`,
    backend: "wifi-rsd",
    transport: "wifi",
    detail: combined.slice(-800),
  };
}

function runUsbIsideload(ipaPath, transportNorm) {
  const cli = findCli();
  const creds = resolveAppleCredentials();
  if (!cli || !creds) {
    return openIloaderFallback(ipaPath);
  }
  console.log(
    `[ios:install] isideload CLI (${cli}) via ${creds.source} transport=${transportNorm}`
  );
  const r = spawnSync(cli, ["install", "--transport", transportNorm, path.resolve(ipaPath)], {
    encoding: "utf8",
    env: {
      ...credEnv(creds),
      IOS_INSTALL_TRANSPORT: transportNorm,
    },
    windowsHide: true,
    timeout: 10 * 60 * 1000,
  });
  const out = ((r.stdout || "") + (r.stderr || "")).trim();
  if (r.status === 0) {
    return {
      code: 0,
      message: out || "installed",
      backend: "isideload",
      transport: transportNorm,
    };
  }
  if (r.status === 2 || /HUMAN_REQUIRED|2FA|two.?factor/i.test(out)) {
    console.warn("[ios:install] isideload HUMAN_REQUIRED → iLoader fallback");
    const fb = openIloaderFallback(ipaPath);
    fb.detail = out.slice(0, 500);
    return fb;
  }
  console.warn(`[ios:install] isideload exit ${r.status}: ${out.slice(0, 400)}`);
  const fb = openIloaderFallback(ipaPath);
  fb.detail = out.slice(0, 500);
  return fb;
}

/**
 * @param {string} ipaPath
 * @param {{ transport?: "auto"|"usb"|"wifi", noLaunch?: boolean }} [opts]
 */
export async function installIpa(ipaPath, opts = {}) {
  const abs = path.resolve(ipaPath);
  if (!fs.existsSync(abs)) {
    return { code: 1, message: `IPA introuvable: ${abs}`, backend: "none" };
  }

  const transport = String(
    opts.transport || process.env.IOS_INSTALL_TRANSPORT || "auto"
  )
    .trim()
    .toLowerCase();
  const transportNorm =
    transport === "network" || transport === "wi-fi" ? "wifi" : transport;
  if (!["auto", "usb", "wifi"].includes(transportNorm)) {
    return {
      code: 1,
      message: `transport invalide: ${transport} (auto|usb|wifi)`,
      backend: "none",
    };
  }

  const noLaunch = Boolean(opts.noLaunch);
  const expect = opts.expect || null;

  if (transportNorm === "wifi" || transportNorm === "auto") {
    let ipaInfo = null;
    try {
      ipaInfo = readBundleInfo(abs);
    } catch (e) {
      return { code: 1, message: `IPA unreadable: ${e.message}`, backend: "none" };
    }
    console.log("========== DEPLOY SOURCE ==========");
    console.log(`IPA:      ${abs}`);
    console.log(`VERSION:  ${ipaInfo.version}`);
    console.log(`BUILD:    ${ipaInfo.build}`);
    console.log(`BUNDLE:   ${ipaInfo.bundle_id}`);
    console.log(`TRANSPORT: RemotePairing → Trusted Tunnel → RSD`);
    console.log(`USB:       must be ABSENT for --wifi`);
    console.log("===================================");

    const signed = signIpa(abs, { expect });
    if (signed.code !== 0) {
      // Strict: never fall back to a previously signed older .app.
      if (transportNorm === "wifi") return signed;
      console.warn(`[ios:install] sign/wifi prep failed → USB fallback: ${signed.message}`);
    } else {
      const wifi = runWifiRsd(signed.signedApp, {
        noLaunch,
        expectVersion: ipaInfo.version,
        expectBuild: ipaInfo.build,
      });
      if (wifi.code === 0) {
        return { ...wifi, signedApp: signed.signedApp, ipaInfo, signedInfo: signed.signedInfo };
      }
      if (transportNorm === "wifi") return wifi;
      console.warn(`[ios:install] Wi-Fi RSD failed → USB fallback: ${wifi.message}`);
    }
  }

  // USB (or usbmux Network lockdown) historical path
  const usbTransport = transportNorm === "wifi" ? "usb" : transportNorm === "auto" ? "usb" : transportNorm;
  return runUsbIsideload(abs, usbTransport === "auto" ? "auto" : "usb");
}

// CLI entry
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  let transport = process.env.IOS_INSTALL_TRANSPORT || "auto";
  let ipa = null;
  let noLaunch = false;
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--transport" && argv[i + 1]) transport = argv[++i];
    else if (argv[i] === "--wifi") transport = "wifi";
    else if (argv[i] === "--usb") transport = "usb";
    else if (argv[i] === "--auto") transport = "auto";
    else if (argv[i] === "--no-launch") noLaunch = true;
    else if (!argv[i].startsWith("-") && !ipa) ipa = argv[i];
  }
  if (!ipa) {
    console.error(
      "Usage: node scripts/ios/install.mjs [--auto|--usb|--wifi] [--no-launch] [--transport auto|usb|wifi] <ipa>"
    );
    process.exit(1);
  }
  installIpa(ipa, { transport, noLaunch }).then((r) => {
    console.log(JSON.stringify(r, null, 2));
    process.exit(r.code === 2 ? 2 : r.code === 0 ? 0 : 1);
  });
}
