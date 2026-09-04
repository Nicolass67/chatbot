/**
 * Crée (idempotent) une Access Application dédiée au path /api
 * avec policy Bypass Everyone — sans modifier les autres apps.
 *
 * Usage:
 *   node scripts/cloudflare-access-api-bypass.mjs
 *
 * Lit deploy/cloudflare-api.env :
 *   CLOUDFLARE_API_TOKEN=...
 *   CLOUDFLARE_ACCOUNT_ID=...
 *
 * Permission token requise :
 *   Account → Access: Apps and Policies → Edit
 */
import fs from "node:fs";
import path from "node:path";

const ENV_PATH = path.join(process.cwd(), "deploy", "cloudflare-api.env");
const MACHINE_ENV_PATH = path.join(process.cwd(), "deploy", "boot", "machine.env");
const PLACEHOLDER_HOST = "your-worker.example.workers.dev";
const APP_NAME = "Chatbot API Bypass";
const LOGIN_APP_NAME = "Chatbot Native Login";

function loadEnv(file) {
  const out = {};
  if (!fs.existsSync(file)) return out;
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue;
    const i = line.indexOf("=");
    if (i < 0) continue;
    out[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  }
  return out;
}

function resolvePublicHost() {
  const fromEnv = process.env.CHATBOT_PUBLIC_HOST?.trim();
  if (fromEnv) return fromEnv.replace(/^https?:\/\//, "").replace(/\/.*$/, "");

  const apiEnv = loadEnv(ENV_PATH);
  if (apiEnv.CHATBOT_PUBLIC_HOST?.trim()) {
    return apiEnv.CHATBOT_PUBLIC_HOST.trim()
      .replace(/^https?:\/\//, "")
      .replace(/\/.*$/, "");
  }

  const machine = loadEnv(MACHINE_ENV_PATH);
  const base = machine.WORKER_BASE_URL?.trim();
  if (base) {
    try {
      return new URL(base).host;
    } catch {
      /* fall through */
    }
  }
  return PLACEHOLDER_HOST;
}

const DOMAIN = resolvePublicHost();
const APP_DOMAIN_WITH_PATH = `${DOMAIN}/api`;
const LOGIN_DOMAIN = `${DOMAIN}/api/auth/app-session/start`;

async function cf(token, method, urlPath, body) {
  const res = await fetch(`https://api.cloudflare.com/client/v4${urlPath}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json();
  if (!json.success) {
    const err = json.errors?.[0];
    throw new Error(
      `${method} ${urlPath} → ${err?.code ?? res.status}: ${err?.message ?? res.statusText}`
    );
  }
  return json.result;
}

function appMatchesApiPath(app) {
  const domain = app.domain || "";
  if (domain === APP_DOMAIN_WITH_PATH || domain === `${DOMAIN}/api/*`) {
    return true;
  }
  const dests = app.destinations || [];
  return dests.some((d) => {
    const uri = d.uri || d;
    return (
      typeof uri === "string" &&
      (uri.includes(`${DOMAIN}/api`) || uri.endsWith("/api") || uri.includes("/api/*"))
    );
  });
}

async function main() {
  if (!fs.existsSync(ENV_PATH)) {
    throw new Error(`Missing ${ENV_PATH}`);
  }
  const env = loadEnv(ENV_PATH);
  const token = env.CLOUDFLARE_API_TOKEN;
  const accountId = env.CLOUDFLARE_ACCOUNT_ID;
  if (!token || !accountId) {
    throw new Error("CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID required");
  }

  console.log("Listing Access applications…");
  const apps = await cf(
    token,
    "GET",
    `/accounts/${accountId}/access/apps?per_page=100`
  );
  console.log(`Found ${apps.length} app(s):`);
  for (const a of apps) {
    console.log(` - ${a.name} | ${a.domain || "(multi)"} | id=${a.id}`);
  }

  let app = apps.find(
    (a) => a.name === APP_NAME || appMatchesApiPath(a)
  );

  if (app) {
    console.log(`Reusing existing app: ${app.name} (${app.id})`);
  } else {
    console.log(`Creating app ${APP_NAME} on ${APP_DOMAIN_WITH_PATH}…`);
    app = await cf(token, "POST", `/accounts/${accountId}/access/apps`, {
      name: APP_NAME,
      type: "self_hosted",
      domain: APP_DOMAIN_WITH_PATH,
      session_duration: "24h",
      auto_redirect_to_identity: false,
      app_launcher_visible: false,
    });
    console.log(`Created app id=${app.id}`);
  }

  const policies = await cf(
    token,
    "GET",
    `/accounts/${accountId}/access/apps/${app.id}/policies`
  );
  const hasBypass = policies.some(
    (p) =>
      p.decision === "bypass" &&
      (p.name === "Bypass API Everyone" ||
        p.include?.some((r) => r.everyone !== undefined))
  );

  if (hasBypass) {
    console.log("Bypass policy already present — OK");
  } else {
    console.log("Creating Bypass Everyone policy…");
    await cf(
      token,
      "POST",
      `/accounts/${accountId}/access/apps/${app.id}/policies`,
      {
        name: "Bypass API Everyone",
        decision: "bypass",
        precedence: 1,
        include: [{ everyone: {} }],
      }
    );
    console.log("Bypass policy created");
  }

  // Path plus spécifique : Access reste obligatoire pour mint le Bearer (ADR 001).
  let loginApp = apps.find(
    (a) => a.name === LOGIN_APP_NAME || a.domain === LOGIN_DOMAIN
  );
  if (loginApp) {
    console.log(`Reusing login app: ${loginApp.name} (${loginApp.id})`);
  } else {
    console.log(`Creating login app ${LOGIN_APP_NAME} on ${LOGIN_DOMAIN}…`);
    loginApp = await cf(token, "POST", `/accounts/${accountId}/access/apps`, {
      name: LOGIN_APP_NAME,
      type: "self_hosted",
      domain: LOGIN_DOMAIN,
      session_duration: "24h",
      auto_redirect_to_identity: true,
      app_launcher_visible: false,
    });
    console.log(`Created login app id=${loginApp.id}`);
  }

  const loginPolicies = await cf(
    token,
    "GET",
    `/accounts/${accountId}/access/apps/${loginApp.id}/policies`
  );
  const hasLoginAllow = loginPolicies.some(
    (p) =>
      p.decision === "allow" &&
      p.include?.some((r) => r.cloudflare_account_member !== undefined)
  );
  if (hasLoginAllow) {
    console.log("Login Allow policy already present — OK");
  } else {
    console.log("Creating login Allow (Cloudflare account members)…");
    await cf(
      token,
      "POST",
      `/accounts/${accountId}/access/apps/${loginApp.id}/policies`,
      {
        name: "Cloudflare account members",
        decision: "allow",
        precedence: 1,
        include: [{ cloudflare_account_member: { account_id: accountId } }],
      }
    );
    console.log("Login Allow policy created");
  }

  console.log("\nDone. Existing Worker Access app/policies were not modified.");
  console.log("Next: build IPA (Actions → iOS Native IPA) and test native login.");
}

main().catch((err) => {
  console.error(err.message || err);
  if (String(err.message).includes("10000") || String(err.message).includes("Authentication")) {
    console.error(`
Le token dans deploy/cloudflare-api.env n'a PAS la permission Access.
Recrée un token :
  https://dash.cloudflare.com/profile/api-tokens
  Permission: Account → Access: Apps and Policies → Edit
Remplace CLOUDFLARE_API_TOKEN dans deploy/cloudflare-api.env puis relance :
  node scripts/cloudflare-access-api-bypass.mjs
`);
  }
  process.exit(1);
});
