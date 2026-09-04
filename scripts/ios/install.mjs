/**
 * Install IPA on physical iPhone.
 * Primary: isideload CLI (scripts/ios/tools/isideload-cli)
 * Fallback: iLoader GUI → INSTALL_HUMAN_REQUIRED (exit 2)
 *
 * Credentials (never git):
 *   APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD (or APPLE_PASSWORD)
 *   or Windows Credential Manager target "ChatbotAppleID"
 */
import { spawn, spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "../..");
const CRED_TARGET = "ChatbotAppleID";

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
# Prefer cmdkey listing + CredRead via WinAPI is heavy; use CredentialManager module if present
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
# Fallback: Windows.Security.Credentials via PowerShell + vault (generic)
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

/**
 * @param {string} ipaPath
 * @returns {Promise<{code:number, humanRequired?:boolean, message:string, backend:string}>}
 */
export async function installIpa(ipaPath) {
  const abs = path.resolve(ipaPath);
  if (!fs.existsSync(abs)) {
    return { code: 1, message: `IPA introuvable: ${abs}`, backend: "none" };
  }

  const cli = findCli();
  const creds = resolveAppleCredentials();

  if (cli && creds) {
    console.log(`[ios:install] isideload CLI (${cli}) via ${creds.source}`);
    const r = spawnSync(
      cli,
      ["install", abs],
      {
        encoding: "utf8",
        env: {
          ...process.env,
          APPLE_ID: creds.appleId,
          APPLE_APP_SPECIFIC_PASSWORD: creds.password,
          APPLE_PASSWORD: creds.password,
        },
        windowsHide: true,
        timeout: 10 * 60 * 1000,
      }
    );
    const out = ((r.stdout || "") + (r.stderr || "")).trim();
    if (r.status === 0) {
      return { code: 0, message: out || "installed", backend: "isideload" };
    }
    if (r.status === 2 || /HUMAN_REQUIRED|2FA|two.?factor/i.test(out)) {
      console.warn("[ios:install] isideload HUMAN_REQUIRED → iLoader fallback");
      const fb = openIloaderFallback(abs);
      fb.detail = out.slice(0, 500);
      return fb;
    }
    console.warn(`[ios:install] isideload exit ${r.status}: ${out.slice(0, 400)}`);
    const fb = openIloaderFallback(abs);
    fb.detail = out.slice(0, 500);
    return fb;
  }

  if (!cli) {
    console.warn("[ios:install] isideload CLI absente — fallback iLoader");
  } else if (!creds) {
    console.warn(
      `[ios:install] Pas de credentials (APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD ou vault ${CRED_TARGET}) — fallback iLoader`
    );
  }
  return openIloaderFallback(abs);
}

// CLI entry
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const ipa = process.argv[2];
  if (!ipa) {
    console.error("Usage: node scripts/ios/install.mjs <ipa>");
    process.exit(1);
  }
  installIpa(ipa).then((r) => {
    console.log(JSON.stringify(r, null, 2));
    process.exit(r.code === 2 ? 2 : r.code === 0 ? 0 : 1);
  });
}
