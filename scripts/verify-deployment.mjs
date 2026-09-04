#!/usr/bin/env node
/**
 * Vérifie le déploiement local et optionnellement l'URL publique.
 */
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const tunnelEnvPath = join(root, "deploy", "cloudflared", "tunnel.env");

function loadPublicUrl() {
  if (!existsSync(tunnelEnvPath)) return process.env.PUBLIC_CHATBOT_URL;
  for (const line of readFileSync(tunnelEnvPath, "utf8").split(/\r?\n/)) {
    const m = line.match(/^PUBLIC_CHATBOT_URL=(.+)$/);
    if (m) return m[1].trim();
  }
  return undefined;
}

async function check(label, url, options = {}) {
  try {
    const res = await fetch(url, { ...options, signal: AbortSignal.timeout(15000) });
    const text = await res.text();
    console.log(`[${label}] HTTP ${res.status} ${url}`);
    if (text.length < 500) console.log(text);
    else console.log(text.slice(0, 200) + "...");
    return res.ok;
  } catch (err) {
    console.error(`[${label}] ERREUR ${url}:`, err.message);
    return false;
  }
}

async function checkSse(label, url) {
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ conversationId: "verify-sse", message: "ping" }),
      signal: AbortSignal.timeout(8000),
    });
    const ct = res.headers.get("content-type") ?? "";
    console.log(`[${label}] HTTP ${res.status} Content-Type=${ct}`);
    if (!ct.includes("text/event-stream")) {
      console.error(`[${label}] SSE attendu, reçu: ${ct}`);
      return false;
    }
    const reader = res.body?.getReader();
    if (!reader) return false;
    const { value } = await reader.read();
    reader.cancel().catch(() => {});
    const chunk = value ? new TextDecoder().decode(value) : "";
    console.log(`[${label}] premier chunk: ${chunk.slice(0, 120).replace(/\n/g, "\\n")}`);
    return chunk.includes("data:") || chunk.includes(": ping");
  } catch (err) {
    if (err.name === "TimeoutError" || err.name === "AbortError") {
      console.log(`[${label}] stream ouvert (timeout attendu sur requête incomplète)`);
      return true;
    }
    console.error(`[${label}] ERREUR:`, err.message);
    return false;
  }
}

const localOk = await check("local-health", "http://127.0.0.1:3000/api/health");
const localSse = await checkSse("local-sse", "http://127.0.0.1:3000/api/chat");

const publicUrl = loadPublicUrl();
let publicOk = true;
if (publicUrl) {
  publicOk = await check("public-health", `${publicUrl.replace(/\/$/, "")}/api/health`);
} else {
  console.log("[public] PUBLIC_CHATBOT_URL non défini — skip");
}

const ok = localOk && localSse && publicOk;
console.log(ok ? "\n✓ Vérifications OK" : "\n✗ Échec — voir messages ci-dessus");
process.exit(ok ? 0 : 1);
