import { NextResponse } from "next/server";
import {
  getPerfSession,
  recordApiTiming,
  setPerfSession,
} from "@/lib/perf/audit";

type RouteContext = { params?: Promise<Record<string, string>> };

type Handler = (
  request: Request,
  context: RouteContext
) => Promise<Response> | Response;

/**
 * Wrap a route handler to record wall-clock + DB delta for the audit.
 * Uses x-perf-session header when present.
 */
export function withApiTiming(handler: Handler): Handler {
  return async (request, context) => {
    const sessionHeader = request.headers.get("x-perf-session");
    const prev = getPerfSession();
    if (sessionHeader) setPerfSession(sessionHeader);

    const url = new URL(request.url);
    const { getPerfAuditSnapshot } = await import("@/lib/perf/audit");
    const before = getPerfAuditSnapshot(sessionHeader ?? prev).rawQueryCount;
    const beforeDbTotal =
      getPerfAuditSnapshot(sessionHeader ?? prev).db.totalMs;

    const t0 = performance.now();
    let status = 500;
    try {
      const res = await handler(request, context);
      status = res.status;
      const durationMs = performance.now() - t0;
      const afterSnap = getPerfAuditSnapshot(sessionHeader ?? getPerfSession());
      const dbQueryCount = afterSnap.rawQueryCount - before;
      const dbTotalMs = afterSnap.db.totalMs - beforeDbTotal;

      recordApiTiming({
        method: request.method,
        path: url.pathname + url.search,
        durationMs,
        status,
        dbQueryCount,
        dbTotalMs,
      });

      const headers = new Headers(res.headers);
      headers.set(
        "Server-Timing",
        `total;dur=${durationMs.toFixed(1)}, db;dur=${dbTotalMs.toFixed(1)}`
      );
      headers.set("x-perf-db-queries", String(dbQueryCount));
      headers.set("x-perf-db-ms", dbTotalMs.toFixed(2));
      headers.set("x-perf-api-ms", durationMs.toFixed(2));

      return new NextResponse(res.body, {
        status: res.status,
        statusText: res.statusText,
        headers,
      });
    } catch (err) {
      const durationMs = performance.now() - t0;
      recordApiTiming({
        method: request.method,
        path: url.pathname + url.search,
        durationMs,
        status,
        dbQueryCount: 0,
        dbTotalMs: 0,
      });
      throw err;
    } finally {
      if (sessionHeader) setPerfSession(prev);
    }
  };
}
