/**
 * Temporary navigation performance audit instrumentation.
 * Collects SQLite query timings and labeled nav sessions.
 * Remove after the audit.
 */

export type DbQueryRecord = {
  sql: string;
  method: string;
  durationMs: number;
  rowEstimate: number | null;
  at: number;
  sessionId: string | null;
};

export type ApiTimingRecord = {
  method: string;
  path: string;
  durationMs: number;
  status: number;
  dbQueryCount: number;
  dbTotalMs: number;
  at: number;
  sessionId: string | null;
};

type PerfStore = {
  enabled: boolean;
  sessionId: string | null;
  queries: DbQueryRecord[];
  apis: ApiTimingRecord[];
  labels: Array<{ at: number; label: string; sessionId: string | null }>;
};

declare global {
  // eslint-disable-next-line no-var
  var __perfAudit: PerfStore | undefined;
}

function store(): PerfStore {
  if (!global.__perfAudit) {
    global.__perfAudit = {
      enabled: true,
      sessionId: null,
      queries: [],
      apis: [],
      labels: [],
    };
  }
  return global.__perfAudit;
}

export function setPerfSession(sessionId: string | null) {
  store().sessionId = sessionId;
}

export function getPerfSession(): string | null {
  return store().sessionId;
}

export function labelPerf(label: string) {
  const s = store();
  s.labels.push({ at: Date.now(), label, sessionId: s.sessionId });
}

export function recordDbQuery(input: {
  sql: string;
  method: string;
  durationMs: number;
  rowEstimate?: number | null;
}) {
  const s = store();
  if (!s.enabled) return;
  const sql = input.sql.replace(/\s+/g, " ").trim().slice(0, 500);
  s.queries.push({
    sql,
    method: input.method,
    durationMs: Math.round(input.durationMs * 1000) / 1000,
    rowEstimate: input.rowEstimate ?? null,
    at: Date.now(),
    sessionId: s.sessionId,
  });
}

export function recordApiTiming(input: {
  method: string;
  path: string;
  durationMs: number;
  status: number;
  dbQueryCount: number;
  dbTotalMs: number;
}) {
  const s = store();
  if (!s.enabled) return;
  s.apis.push({
    ...input,
    durationMs: Math.round(input.durationMs * 1000) / 1000,
    dbTotalMs: Math.round(input.dbTotalMs * 1000) / 1000,
    at: Date.now(),
    sessionId: s.sessionId,
  });
}

export function resetPerfAudit(sessionId?: string) {
  const s = store();
  s.queries = [];
  s.apis = [];
  s.labels = [];
  s.sessionId = sessionId ?? null;
}

function summarizeQueries(queries: DbQueryRecord[]) {
  const bySql = new Map<
    string,
    { count: number; totalMs: number; maxMs: number; sql: string }
  >();
  for (const q of queries) {
    const key = q.sql;
    const prev = bySql.get(key) ?? {
      count: 0,
      totalMs: 0,
      maxMs: 0,
      sql: key,
    };
    prev.count += 1;
    prev.totalMs += q.durationMs;
    prev.maxMs = Math.max(prev.maxMs, q.durationMs);
    bySql.set(key, prev);
  }
  const grouped = [...bySql.values()].sort((a, b) => b.totalMs - a.totalMs);
  const duplicates = grouped.filter((g) => g.count > 1);
  return {
    count: queries.length,
    totalMs: Math.round(queries.reduce((a, q) => a + q.durationMs, 0) * 1000) / 1000,
    slowest: [...queries].sort((a, b) => b.durationMs - a.durationMs).slice(0, 10),
    bySql: grouped.slice(0, 20),
    duplicates: duplicates.slice(0, 20),
  };
}

export function getPerfAuditSnapshot(sessionId?: string | null) {
  const s = store();
  const filter = (sessionId?: string | null) => {
    if (!sessionId) return { queries: s.queries, apis: s.apis, labels: s.labels };
    return {
      queries: s.queries.filter((q) => q.sessionId === sessionId),
      apis: s.apis.filter((a) => a.sessionId === sessionId),
      labels: s.labels.filter((l) => l.sessionId === sessionId),
    };
  };
  const data = filter(sessionId);
  return {
    sessionId: sessionId ?? s.sessionId,
    collectedAt: new Date().toISOString(),
    labels: data.labels,
    db: summarizeQueries(data.queries),
    api: {
      count: data.apis.length,
      totalMs:
        Math.round(data.apis.reduce((a, x) => a + x.durationMs, 0) * 1000) / 1000,
      calls: [...data.apis].sort((a, b) => b.durationMs - a.durationMs),
    },
    rawQueryCount: data.queries.length,
  };
}

/** Wrap better-sqlite3 Database to time prepare/run/get/all/exec. */
export function instrumentSqliteDatabase<T extends object>(sqlite: T): T {
  // Disabled: previous wrappers recursed into Statement.all/get/run under
  // better-sqlite3 + HMR (Maximum call stack size exceeded → API 500).
  // Keep the rest of the perf audit (API timings / client profiler) intact.
  return sqlite;
}
