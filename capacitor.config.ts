import type { CapacitorConfig } from "@capacitor/cli";
import fs from "node:fs";
import path from "node:path";

/**
 * Shell iOS stable — contenu applicatif 100 % remote.
 *
 * allowNavigation (doit rester dans la WKWebView, sinon iOS ouvre Chrome) :
 * - hostname Chatbot (app)
 * - *.cloudflareaccess.com (team Access + oauth-callbacks)
 * - dash.cloudflare.com (IdP Cloudflare Access)
 * - accounts.google.com (+ miroirs Google) : login Gmail de l’IdP Access
 * OAuth Gmail *API* (settings) reste via @capacitor/browser (appel explicite).
 *
 * Local override (gitignored): capacitor.local.json
 *   { "publicOrigin": "https://…", "accessTeamHost": "….cloudflareaccess.com" }
 * Or env: CHATBOT_PUBLIC_ORIGIN / CHATBOT_ACCESS_TEAM_HOST
 */
const PLACEHOLDER_ORIGIN = "https://your-worker.example.workers.dev";
const PLACEHOLDER_TEAM = "your-team.cloudflareaccess.com";

function loadLocalCapacitor(): {
  publicOrigin?: string;
  accessTeamHost?: string;
} {
  const localPath = path.join(process.cwd(), "capacitor.local.json");
  if (!fs.existsSync(localPath)) return {};
  try {
    return JSON.parse(fs.readFileSync(localPath, "utf8")) as {
      publicOrigin?: string;
      accessTeamHost?: string;
    };
  } catch {
    return {};
  }
}

const local = loadLocalCapacitor();
const PUBLIC_ORIGIN =
  local.publicOrigin?.trim() ||
  process.env.CHATBOT_PUBLIC_ORIGIN?.trim() ||
  PLACEHOLDER_ORIGIN;
const ACCESS_TEAM_HOST =
  local.accessTeamHost?.trim() ||
  process.env.CHATBOT_ACCESS_TEAM_HOST?.trim() ||
  PLACEHOLDER_TEAM;

let appHost: string;
try {
  appHost = new URL(PUBLIC_ORIGIN).host;
} catch {
  appHost = "your-worker.example.workers.dev";
}

const config: CapacitorConfig = {
  appId: "fr.nicolazer.chatbot",
  appName: "Chatbot",
  webDir: "www",
  server: {
    url: PUBLIC_ORIGIN,
    cleartext: false,
    allowNavigation: [
      appHost,
      "*.cloudflareaccess.com",
      ACCESS_TEAM_HOST,
      "oauth-callbacks.cloudflareaccess.com",
      "dash.cloudflare.com",
      // IdP Access « Sign in with Google / Gmail » (sinon → Chrome)
      "accounts.google.com",
      "accounts.youtube.com",
      "google.com",
      "www.google.com",
    ],
  },
  ios: {
    contentInset: "never",
    preferredContentMode: "mobile",
    // Remplit l’écran (iPhone 14 Plus home indicator) — safe-area géré en CSS
    scrollEnabled: true,
    backgroundColor: "#18181a",
  },
  backgroundColor: "#18181a",
  plugins: {
    SplashScreen: {
      // Ne pas bloquer la page Cloudflare Access : auto-hide rapide,
      // puis le loader HTML (#app-boot) couvre l’hydratation React.
      launchAutoHide: true,
      launchShowDuration: 2500,
      backgroundColor: "#18181a",
      showSpinner: true,
      spinnerColor: "#5b8fd4",
      launchFadeOutDuration: 280,
    },
    Keyboard: {
      resize: "body",
      resizeOnFullScreen: true,
    },
    StatusBar: {
      style: "DARK",
      backgroundColor: "#18181a",
    },
  },
};

export default config;
