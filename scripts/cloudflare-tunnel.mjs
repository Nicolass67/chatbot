#!/usr/bin/env node
/**
 * Lance cloudflared pour le Chatbot (tunnel nommé — compatible SSE).
 * N'utilise PAS trycloudflare / Quick Tunnel.
 */
import { spawn } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const deployDir = join(root, "deploy", "cloudflared");
const tunnelEnvPath = join(deployDir, "tunnel.env");
const configPath = join(deployDir, "config.yml");

const CLOUDFLARED_CANDIDATES = [
  "C:\\Program Files (x86)\\cloudflared\\cloudflared.exe",
  "C:\\Program Files\\cloudflared\\cloudflared.exe",
  "cloudflared",
];

function loadTunnelEnv() {
  if (!existsSync(tunnelEnvPath)) return {};
  const env = {};
  for (const line of readFileSync(tunnelEnvPath, "utf8").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    env[trimmed.slice(0, eq).trim()] = trimmed.slice(eq + 1).trim();
  }
  return env;
}

function resolveCloudflared() {
  for (const candidate of CLOUDFLARED_CANDIDATES) {
    if (candidate.includes("\\") && existsSync(candidate)) return candidate;
  }
  return "cloudflared";
}

function runCloudflared(args) {
  const bin = resolveCloudflared();
  console.log(`[tunnel] ${bin} ${args.join(" ")}`);
  const child = spawn(bin, args, { stdio: "inherit", shell: false });
  child.on("exit", (code) => process.exit(code ?? 1));
}

const tunnelEnv = loadTunnelEnv();
const token = tunnelEnv.CLOUDFLARE_TUNNEL_TOKEN || process.env.CLOUDFLARE_TUNNEL_TOKEN;

if (token) {
  runCloudflared(["tunnel", "run", "--token", token]);
} else if (existsSync(configPath)) {
  runCloudflared(["tunnel", "--config", configPath, "run"]);
} else {
  console.error(`
Configuration tunnel manquante.

Option A (recommandée) — tunnel géré Cloudflare :
  1. Copier deploy/cloudflared/tunnel.env.example → deploy/cloudflared/tunnel.env
  2. Coller CLOUDFLARE_TUNNEL_TOKEN depuis le dashboard Cloudflare
  3. Relancer : npm run tunnel:run

Option B — config locale :
  1. cloudflared tunnel login
  2. cloudflared tunnel create chatbot
  3. Copier deploy/cloudflared/config.example.yml → config.yml et adapter

Voir docs/DEPLOYMENT.md
`);
  process.exit(1);
}
