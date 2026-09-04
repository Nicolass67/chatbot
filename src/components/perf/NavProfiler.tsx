"use client";

import { useEffect } from "react";

type NavReport = {
  label: string;
  sessionId: string;
  clickToUrlChangeMs: number | null;
  firstContentMs: number | null;
  interactiveMs: number | null;
  quietNetworkMs: number | null;
  js: {
    count: number;
    transferKb: number;
    encodedKb: number;
    urls: Array<{ url: string; transferKb: number; durationMs: number }>;
  };
  css: { count: number; transferKb: number };
  flights: Array<{ url: string; durationMs: number; transferKb: number }>;
  api: Array<{
    url: string;
    durationMs: number;
    transferKb: number;
    startOffsetMs: number;
    responseEndOffsetMs: number;
  }>;
  apiWallMs: number;
  apiSumMs: number;
  longTasks: Array<{ startMs: number; durationMs: number; totalMs: number }>;
  longTasksTotalMs: number;
  serverDb: unknown;
};

type PendingNav = {
  from: string;
  to: string;
  sessionId: string;
  tClick: number;
  tUrl: number | null;
  tFirstContent: number | null;
  longTasks: Array<{ startMs: number; durationMs: number }>;
};

function kb(bytes: number) {
  return Math.round((bytes / 1024) * 10) / 10;
}

function destPath(href: string): string | null {
  try {
    const u = new URL(href, location.origin);
    if (u.origin !== location.origin) return null;
    return u.pathname + u.search;
  } catch {
    return null;
  }
}

function isMainNav(path: string) {
  return (
    path.startsWith("/chat") ||
    path.startsWith("/mail") ||
    path.startsWith("/files") ||
    path.startsWith("/settings")
  );
}

function collectResources(since: number): PerformanceResourceTiming[] {
  return performance
    .getEntriesByType("resource")
    .filter((e): e is PerformanceResourceTiming => e.startTime >= since - 2);
}

async function buildReport(pending: PendingNav, tQuiet: number): Promise<NavReport> {
  const origin = pending.tClick;
  const resources = collectResources(origin);

  const jsResources = resources.filter(
    (r) =>
      r.initiatorType === "script" ||
      r.name.includes("/_next/static/chunks/") ||
      (r.name.includes(".js") && !r.name.includes("/api/"))
  );
  const cssResources = resources.filter(
    (r) =>
      r.initiatorType === "link" ||
      r.name.includes(".css") ||
      r.name.includes("/_next/static/css/")
  );
  const flights = resources.filter((r) => {
    const n = r.name;
    if (n.includes("/api/")) return false;
    return (
      n.includes("?_rsc=") ||
      n.includes("&_rsc=") ||
      (r.initiatorType === "fetch" &&
        (n.includes("/chat") ||
          n.includes("/mail") ||
          n.includes("/files") ||
          n.includes("/settings")))
    );
  });
  const api = resources.filter(
    (r) => r.name.includes("/api/") && !r.name.includes("/api/perf/")
  );

  const apiCalls = api
    .map((r) => ({
      url: r.name.replace(location.origin, ""),
      durationMs: Math.round(r.duration * 10) / 10,
      transferKb: kb(r.transferSize || r.encodedBodySize || 0),
      startOffsetMs: Math.round(r.startTime - origin),
      responseEndOffsetMs: Math.round(r.responseEnd - origin),
    }))
    .sort((a, b) => a.startOffsetMs - b.startOffsetMs);

  let apiWallMs = 0;
  if (api.length > 0) {
    apiWallMs = Math.round(
      Math.max(...api.map((r) => r.responseEnd)) -
        Math.min(...api.map((r) => r.startTime))
    );
  }

  let serverDb: unknown = null;
  try {
    const res = await fetch(
      `/api/perf/audit?session=${encodeURIComponent(pending.sessionId)}`
    );
    if (res.ok) serverDb = await res.json();
  } catch {
    serverDb = null;
  }

  const longTasksTotalMs = pending.longTasks.reduce((a, t) => a + t.durationMs, 0);
  const tInteractive =
    pending.tFirstContent != null
      ? pending.tFirstContent
      : tQuiet;

  return {
    label: `${pending.from} → ${pending.to}`,
    sessionId: pending.sessionId,
    clickToUrlChangeMs:
      pending.tUrl != null ? Math.round(pending.tUrl - pending.tClick) : null,
    firstContentMs:
      pending.tFirstContent != null
        ? Math.round(pending.tFirstContent - pending.tClick)
        : null,
    interactiveMs: Math.round(tInteractive - pending.tClick),
    quietNetworkMs: Math.round(tQuiet - pending.tClick),
    js: {
      count: jsResources.length,
      transferKb: kb(
        jsResources.reduce(
          (a, r) => a + (r.transferSize || r.encodedBodySize || 0),
          0
        )
      ),
      encodedKb: kb(
        jsResources.reduce((a, r) => a + (r.encodedBodySize || 0), 0)
      ),
      urls: jsResources
        .map((r) => ({
          url: r.name.replace(location.origin, ""),
          transferKb: kb(r.transferSize || r.encodedBodySize || 0),
          durationMs: Math.round(r.duration),
        }))
        .sort((a, b) => b.transferKb - a.transferKb)
        .slice(0, 30),
    },
    css: {
      count: cssResources.length,
      transferKb: kb(
        cssResources.reduce(
          (a, r) => a + (r.transferSize || r.encodedBodySize || 0),
          0
        )
      ),
    },
    flights: flights.map((r) => ({
      url: r.name.replace(location.origin, ""),
      durationMs: Math.round(r.duration * 10) / 10,
      transferKb: kb(r.transferSize || r.encodedBodySize || 0),
    })),
    api: apiCalls,
    apiWallMs,
    apiSumMs: Math.round(apiCalls.reduce((a, c) => a + c.durationMs, 0) * 10) / 10,
    longTasks: pending.longTasks.map((t) => ({
      ...t,
      totalMs: t.durationMs,
    })),
    longTasksTotalMs: Math.round(longTasksTotalMs),
    serverDb,
  };
}

/**
 * Temporary soft-navigation profiler.
 * Click sidebar links (Chat/Mail/Files/Settings) — reports go to console + window.__navAudit.
 */
export function NavProfiler() {
  useEffect(() => {
    const reports: NavReport[] = [];
    let pending: PendingNav | null = null;
    let quietTimer: number | null = null;
    let pollTimer: number | null = null;

    const api = {
      reports,
      last: null as NavReport | null,
      pending: () => pending,
    };
    (window as unknown as { __navAudit: typeof api }).__navAudit = api;

    let longTaskObs: PerformanceObserver | null = null;
    try {
      longTaskObs = new PerformanceObserver((list) => {
        if (!pending) return;
        for (const e of list.getEntries()) {
          if (e.startTime >= pending.tClick) {
            pending.longTasks.push({
              startMs: Math.round(e.startTime - pending.tClick),
              durationMs: Math.round(e.duration),
            });
          }
        }
      });
      longTaskObs.observe({
        type: "longtask",
        buffered: true,
      } as PerformanceObserverInit);
    } catch {
      longTaskObs = null;
    }

    const mo = new MutationObserver(() => {
      if (!pending) return;
      if (pending.tUrl == null) {
        const nowPath = location.pathname + location.search;
        if (
          nowPath === pending.to ||
          nowPath.startsWith(pending.to.split("?")[0])
        ) {
          pending.tUrl = performance.now();
        }
      }
      if (pending.tUrl != null && pending.tFirstContent == null) {
        const root =
          document.querySelector("main") ||
          document.querySelector("[data-workspace]") ||
          document.body;
        const text = root?.textContent?.replace(/\s+/g, " ").trim() ?? "";
        if (text.length > 40) {
          pending.tFirstContent = performance.now();
        }
      }
    });
    mo.observe(document.documentElement, {
      childList: true,
      subtree: true,
      characterData: true,
    });

    async function finish() {
      if (!pending) return;
      const current = pending;
      pending = null;
      if (quietTimer) window.clearTimeout(quietTimer);
      if (pollTimer) window.clearInterval(pollTimer);
      quietTimer = null;
      pollTimer = null;

      await new Promise((r) => setTimeout(r, 120));
      const report = await buildReport(current, performance.now());
      reports.push(report);
      api.last = report;
      console.log("%c[NavAudit]", "color:#6cf;font-weight:bold", report);
    }

    function armQuietWatch() {
      if (quietTimer) window.clearTimeout(quietTimer);
      let lastCount = performance.getEntriesByType("resource").length;
      if (pollTimer) window.clearInterval(pollTimer);
      pollTimer = window.setInterval(() => {
        const count = performance.getEntriesByType("resource").length;
        if (count !== lastCount) {
          lastCount = count;
          if (quietTimer) window.clearTimeout(quietTimer);
          quietTimer = window.setTimeout(() => {
            void finish();
          }, 750);
        }
      }, 100);
      quietTimer = window.setTimeout(() => {
        void finish();
      }, 8000);
    }

    const onClick = (event: MouseEvent) => {
      const target = event.target as Element | null;
      const anchor = target?.closest?.("a[href]") as HTMLAnchorElement | null;
      if (!anchor || event.metaKey || event.ctrlKey || event.shiftKey) return;
      if (anchor.target === "_blank") return;

      const to = destPath(anchor.href);
      if (!to || !isMainNav(to)) return;
      const from = location.pathname + location.search;
      if (to === from) return;
      // same section chat→chat is ok to measure but focus on cross-section
      const fromRoot = from.split("/")[1];
      const toRoot = to.split("/")[1];
      if (fromRoot === toRoot && fromRoot === "chat") {
        // still measure chat↔chat if different path
      }

      const sessionId = `nav-${Date.now()}`;
      void fetch("/api/perf/audit", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "reset", sessionId }),
      });

      pending = {
        from,
        to,
        sessionId,
        tClick: performance.now(),
        tUrl: null,
        tFirstContent: null,
        longTasks: [],
      };
      armQuietWatch();
    };

    document.addEventListener("click", onClick, true);
    console.info(
      "[NavAudit] actif — cliquez Chat/Mail/Files/Settings. Résultats: window.__navAudit.reports"
    );

    return () => {
      document.removeEventListener("click", onClick, true);
      mo.disconnect();
      longTaskObs?.disconnect();
      if (quietTimer) window.clearTimeout(quietTimer);
      if (pollTimer) window.clearInterval(pollTimer);
    };
  }, []);

  return null;
}
