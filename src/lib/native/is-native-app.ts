import { Capacitor } from "@capacitor/core";

/** True uniquement dans la WebView Capacitor native (pas Safari / desktop). */
export function isNativeApp(): boolean {
  try {
    return Capacitor.isNativePlatform();
  } catch {
    return false;
  }
}
