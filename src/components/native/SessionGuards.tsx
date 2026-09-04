"use client";

import { useEffect, useState } from "react";
import { useToast } from "@/components/ui/Toast";
import { isNativeApp } from "@/lib/native/is-native-app";

/**
 * Bannière + toasts pour session Access / offline.
 * No-op destructif : ne désactive jamais Access.
 */
export function SessionGuards() {
  const { toast } = useToast();
  const [offline, setOffline] = useState(false);

  useEffect(() => {
    const syncOnline = () => setOffline(!navigator.onLine);
    syncOnline();
    window.addEventListener("online", syncOnline);
    window.addEventListener("offline", syncOnline);

    const onAuth = () => {
      toast("Session Cloudflare Access expirée — reconnexion…", "error");
      window.setTimeout(() => {
        window.location.assign("/");
      }, 1200);
    };

    const onNetwork = () => {
      toast("Connexion réseau interrompue", "error");
    };

    window.addEventListener("chatbot:auth-required", onAuth);
    window.addEventListener("chatbot:network-error", onNetwork);

    return () => {
      window.removeEventListener("online", syncOnline);
      window.removeEventListener("offline", syncOnline);
      window.removeEventListener("chatbot:auth-required", onAuth);
      window.removeEventListener("chatbot:network-error", onNetwork);
    };
  }, [toast]);

  if (!offline) return null;

  return (
    <div
      role="alert"
      className="fixed inset-x-0 top-0 z-[200] bg-error px-3 py-2 text-center text-sm text-white pt-[max(0.5rem,env(safe-area-inset-top))]"
    >
      Hors ligne
      {isNativeApp()
        ? " — vérifiez le réseau ou que le PC / tunnel est allumé."
        : " — vérifiez votre connexion."}
    </div>
  );
}
