/**
 * Vérifie la cohérence Capacitor (shell remote) sans secrets.
 * Source de vérité : capacitor.config.ts (le JSON ios/ est généré par cap sync).
 * Usage: node scripts/verify-capacitor.mjs
 */
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const errors = [];
const warnings = [];

function mustExist(rel) {
  if (!fs.existsSync(path.join(root, rel))) {
    errors.push(`missing: ${rel}`);
  }
}

function readJson(rel) {
  return JSON.parse(fs.readFileSync(path.join(root, rel), "utf8"));
}

mustExist("capacitor.config.ts");
mustExist("www/index.html");
mustExist("ios/App/App.xcodeproj/project.pbxproj");
mustExist(".github/workflows/ios.yml");

const configTs = fs.readFileSync(
  path.join(root, "capacitor.config.ts"),
  "utf8"
);

function resolveServerUrl() {
  const localPath = path.join(root, "capacitor.local.json");
  if (fs.existsSync(localPath)) {
    try {
      const local = JSON.parse(fs.readFileSync(localPath, "utf8"));
      if (typeof local.publicOrigin === "string" && local.publicOrigin.startsWith("https://")) {
        return local.publicOrigin;
      }
    } catch {
      /* fall through */
    }
  }
  if (process.env.CHATBOT_PUBLIC_ORIGIN?.startsWith("https://")) {
    return process.env.CHATBOT_PUBLIC_ORIGIN.trim();
  }
  const placeholder = configTs.match(
    /PLACEHOLDER_ORIGIN\s*=\s*["'](https:\/\/[^"']+)["']/
  );
  if (placeholder?.[1]) return placeholder[1];
  const urlMatch = configTs.match(
    /(?:PUBLIC_ORIGIN|url)\s*[:=]\s*["'](https:\/\/[^"']+)["']/
  );
  return urlMatch?.[1];
}

const serverUrl = resolveServerUrl();
if (!serverUrl) {
  errors.push("could not parse https server.url from capacitor.config.ts");
} else {
  console.log(`[ok] server.url=${serverUrl}`);
}

if (/cleartext\s*:\s*true/.test(configTs)) {
  errors.push("server.cleartext must be false");
}

// allowNavigation is built dynamically (appHost + ACCESS_TEAM_HOST); check structure.
const hasAllowNav = /allowNavigation\s*:\s*\[/.test(configTs);
if (!hasAllowNav) {
  errors.push("missing allowNavigation array in capacitor.config.ts");
}

try {
  if (serverUrl) new URL(serverUrl);
} catch {
  errors.push(`invalid server.url: ${serverUrl}`);
}

if (!/\*\.cloudflareaccess\.com/.test(configTs)) {
  warnings.push(
    "allowNavigation without cloudflareaccess.com — login Access may open Chrome"
  );
}

if (!configTs.includes("dash.cloudflare.com")) {
  warnings.push(
    "allowNavigation missing dash.cloudflare.com — Access IdP Cloudflare opens system browser"
  );
}

if (!configTs.includes("accounts.google.com")) {
  warnings.push(
    "allowNavigation missing accounts.google.com — Access Gmail/Google IdP opens Chrome"
  );
}

// localhost interdit dans le source (placeholders / hosts dynamiques).
const banned = ["localhost", "127.0.0.1"];
for (const b of banned) {
  if (configTs.includes(`"${b}"`) || configTs.includes(`'${b}'`)) {
    errors.push(`allowNavigation too broad (found ${b})`);
  }
}

const generated = path.join(root, "ios/App/App/capacitor.config.json");
if (fs.existsSync(generated)) {
  const nativeConfig = JSON.parse(fs.readFileSync(generated, "utf8"));
  // Generated file may lag until `cap sync`; warn only if local origin is set.
  if (
    nativeConfig?.server?.url &&
    serverUrl &&
    nativeConfig.server.url !== serverUrl
  ) {
    warnings.push(
      `generated ios capacitor.config.json url differs from resolved origin (${nativeConfig.server.url} vs ${serverUrl}) — run cap sync`
    );
  }
} else {
  warnings.push(
    "ios/App/App/capacitor.config.json absent (normal before cap sync)"
  );
}

const pkg = readJson("package.json");
for (const dep of [
  "@capacitor/core",
  "@capacitor/ios",
  "@capacitor/app",
  "@capacitor/browser",
  "@capacitor/keyboard",
  "@capacitor/status-bar",
  "@capacitor/splash-screen",
]) {
  if (!pkg.dependencies?.[dep] && !pkg.devDependencies?.[dep]) {
    errors.push(`missing dependency ${dep}`);
  }
}

const workflow = fs.readFileSync(
  path.join(root, ".github/workflows/ios.yml"),
  "utf8"
);
if (/APPLE_|ASC_|MATCH_|P12|mobileprovision/i.test(workflow)) {
  errors.push("ios.yml appears to reference Apple signing secrets (not wanted)");
}
if (!workflow.includes("CODE_SIGNING_ALLOWED=NO")) {
  errors.push("ios.yml missing unsigned build flags");
}
if (!workflow.includes("upload-artifact")) {
  errors.push("ios.yml missing artifact upload");
}

for (const w of warnings) console.warn(`[warn] ${w}`);
if (errors.length) {
  for (const e of errors) console.error(`[fail] ${e}`);
  process.exit(1);
}

console.log("[ok] Capacitor shell config looks consistent");
