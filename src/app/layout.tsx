import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { BootSplash } from "@/components/native/BootSplash";
import { NativeShell } from "@/components/native/NativeShell";
import { SessionGuards } from "@/components/native/SessionGuards";
import { ToastProvider } from "@/components/ui/Toast";
import { NavProfiler } from "@/components/perf/NavProfiler";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
  display: "swap",
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
  display: "swap",
});

export const metadata: Metadata = {
  title: {
    default: "Chatbot Local",
    template: "%s | Chatbot",
  },
  description: "Assistant IA local avec LM Studio",
  applicationName: "Chatbot",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "Chatbot",
  },
  formatDetection: {
    telephone: false,
    email: false,
    address: false,
  },
  other: {
    "mobile-web-app-capable": "yes",
  },
};

export const viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover" as const,
  themeColor: "#18181a",
};

const bootLoaderCss = `
#app-boot{position:fixed;inset:0;z-index:99999;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:1.25rem;background:#18181a;color:#e2e2e6;font-family:system-ui,-apple-system,sans-serif;transition:opacity .28s ease,visibility .28s ease}
#app-boot.app-boot--done{opacity:0;visibility:hidden;pointer-events:none}
#app-boot .app-boot-wheel{width:2.25rem;height:2.25rem;border-radius:9999px;border:2.5px solid rgba(255,255,255,.12);border-top-color:#5b8fd4;animation:app-boot-spin .7s linear infinite}
#app-boot .app-boot-label{margin:0;font-size:.9375rem;letter-spacing:.01em;opacity:.88}
#app-boot .app-boot-hint{margin:0;font-size:.75rem;opacity:.45;max-width:16rem;text-align:center;line-height:1.4}
@keyframes app-boot-spin{to{transform:rotate(360deg)}}
`;

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="fr" className="dark">
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased`}
      >
        <style dangerouslySetInnerHTML={{ __html: bootLoaderCss }} />
        <div id="app-boot" role="status" aria-live="polite" aria-busy="true">
          <div className="app-boot-wheel" aria-hidden="true" />
          <p className="app-boot-label">Chargement…</p>
          <p className="app-boot-hint">
            Connexion sécurisée et démarrage de l&apos;assistant
          </p>
        </div>
        <ToastProvider>
          <BootSplash />
          <NativeShell />
          <SessionGuards />
          {children}
          <NavProfiler />
        </ToastProvider>
      </body>
    </html>
  );
}
