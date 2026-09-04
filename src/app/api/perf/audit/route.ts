import { NextResponse } from "next/server";
import {
  getPerfAuditSnapshot,
  labelPerf,
  resetPerfAudit,
  setPerfSession,
} from "@/lib/perf/audit";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Temporary audit endpoint — remove after perf investigation. */
export async function GET(request: Request) {
  const url = new URL(request.url);
  const sessionId = url.searchParams.get("session");
  return NextResponse.json(getPerfAuditSnapshot(sessionId));
}

export async function POST(request: Request) {
  const body = (await request.json().catch(() => ({}))) as {
    action?: string;
    sessionId?: string;
    label?: string;
  };

  if (body.action === "reset") {
    resetPerfAudit(body.sessionId ?? `nav-${Date.now()}`);
    return NextResponse.json({
      ok: true,
      sessionId: body.sessionId ?? null,
      snapshot: getPerfAuditSnapshot(),
    });
  }

  if (body.action === "label" && body.label) {
    if (body.sessionId) setPerfSession(body.sessionId);
    labelPerf(body.label);
    return NextResponse.json({ ok: true });
  }

  if (body.action === "setSession") {
    setPerfSession(body.sessionId ?? null);
    return NextResponse.json({ ok: true, sessionId: body.sessionId ?? null });
  }

  return NextResponse.json({ error: "Unknown action" }, { status: 400 });
}
