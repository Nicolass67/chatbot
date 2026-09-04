"use client";

import { useEffect } from "react";
import { App } from "@capacitor/app";
import { Keyboard, KeyboardResize } from "@capacitor/keyboard";
import { SplashScreen } from "@capacitor/splash-screen";
import { StatusBar, Style } from "@capacitor/status-bar";
import { isNativeApp } from "@/lib/native/is-native-app";

/**
 * Init native minimale (no-op hors Capacitor).
 * - Splash jusqu’au premier paint React (BootSplash)
 * - StatusBar dark
 * - Keyboard resize body
 * - Background → event pour abort SSE (ChatView)
 */
export function NativeShell() {
  useEffect(() => {
    if (!isNativeApp()) return;

    let cancelled = false;
    const handles: { remove: () => Promise<void> }[] = [];

    void (async () => {
      try {
        await StatusBar.setStyle({ style: Style.Dark });
      } catch {
        /* ignore */
      }

      try {
        await Keyboard.setResizeMode({ mode: KeyboardResize.Body });
      } catch {
        /* ignore */
      }

      try {
        // Sécurité si le splash natif est encore visible après Access
        await SplashScreen.hide({ fadeOutDuration: 200 });
      } catch {
        /* ignore */
      }

      try {
        const sub = await App.addListener("appStateChange", ({ isActive }) => {
          if (!isActive) {
            window.dispatchEvent(new CustomEvent("chatbot:app-background"));
          }
        });
        if (cancelled) {
          void sub.remove();
        } else {
          handles.push(sub);
        }
      } catch {
        /* ignore */
      }
    })();

    return () => {
      cancelled = true;
      for (const h of handles) void h.remove();
    };
  }, []);

  return null;
}
