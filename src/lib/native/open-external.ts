import { Capacitor } from "@capacitor/core";
import { Browser } from "@capacitor/browser";
import { isNativeApp } from "@/lib/native/is-native-app";

/**
 * Ouvre une URL hors WebView (Browser plugin) en app native,
 * sinon window.open en navigateur.
 * Les navigations same-origin restent dans la WebView via Next Link / router.
 */
export async function openExternal(url: string): Promise<void> {
  const href = resolveAbsoluteUrl(url);
  if (!href) return;

  if (isNativeApp()) {
    await Browser.open({ url: href });
    return;
  }

  window.open(href, "_blank", "noopener,noreferrer");
}

/**
 * OAuth Gmail : en native, naviguer dans la même WKWebView que Cloudflare Access
 * (cookies Access + accounts.google.com déjà en allowNavigation).
 * Browser externe = cookies Access absents + risque redirect_uri / Chrome.
 */
export async function openGmailOAuthStart(): Promise<void> {
  const href = resolveAbsoluteUrl("/api/oauth/gmail/start");
  if (!href) return;

  window.location.assign(href);
}

export function resolveAbsoluteUrl(url: string): string | null {
  const trimmed = url.trim();
  if (!trimmed || trimmed.startsWith("javascript:")) return null;

  try {
    if (typeof window !== "undefined") {
      return new URL(trimmed, window.location.origin).toString();
    }
    return new URL(trimmed).toString();
  } catch {
    return null;
  }
}

/** True si l’URL sort du domaine Chatbot (à ouvrir via Browser). */
export function isExternalHttpUrl(url: string): boolean {
  try {
    const absolute = resolveAbsoluteUrl(url);
    if (!absolute) return false;
    const parsed = new URL(absolute);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      return false;
    }
    if (typeof window === "undefined") return true;
    return parsed.origin !== window.location.origin;
  } catch {
    return false;
  }
}

export function getNativePlatform(): string {
  try {
    return Capacitor.getPlatform();
  } catch {
    return "web";
  }
}
