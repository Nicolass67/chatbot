"use client";

import { useEffect } from "react";
import { SplashScreen } from "@capacitor/splash-screen";
import { isNativeApp } from "@/lib/native/is-native-app";

/**
 * Retire le loader HTML critique + splash Capacitor dès que React est monté.
 */
export function BootSplash() {
  useEffect(() => {
    const boot = document.getElementById("app-boot");
    if (boot) {
      boot.classList.add("app-boot--done");
      window.setTimeout(() => boot.remove(), 320);
    }

    if (!isNativeApp()) return;

    void (async () => {
      try {
        await SplashScreen.hide({ fadeOutDuration: 280 });
      } catch {
        /* ignore */
      }
    })();
  }, []);

  return null;
}
