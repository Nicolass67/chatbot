/** Demandes de démarrage temporaires stockées dans KV (PC éteint au moment de la création). */

export type BootRequestStatus = "pending" | "consumed" | "expired";
export type BootRequestAction = "start" | "restart" | "shutdown";

export interface BootRequestRecord {
  requestId: string;
  createdAt: string;
  expiresAt: string;
  status: BootRequestStatus;
  action: BootRequestAction;
}

export interface BootRequestPeek {
  pending: boolean;
  requestId?: string;
  expiresAt?: string;
  status?: BootRequestStatus;
  action?: BootRequestAction;
}

const KV_KEY = "boot:current";
const DEFAULT_TTL_SECONDS = 300;

export function bootRequestTtlSeconds(env: {
  BOOT_REQUEST_TTL_SECONDS?: string;
}): number {
  const parsed = Number.parseInt(env.BOOT_REQUEST_TTL_SECONDS ?? "", 10);
  if (Number.isFinite(parsed) && parsed >= 60 && parsed <= 900) {
    return parsed;
  }
  return DEFAULT_TTL_SECONDS;
}

function nowIso(): string {
  return new Date().toISOString();
}

function isExpired(record: BootRequestRecord, now = Date.now()): boolean {
  return Date.parse(record.expiresAt) <= now;
}

function normalizeRecord(
  record: BootRequestRecord,
  now = Date.now()
): BootRequestRecord {
  if (record.status === "pending" && isExpired(record, now)) {
    return { ...record, status: "expired" };
  }
  return record;
}

export async function readBootRequest(
  kv: KVNamespace
): Promise<BootRequestRecord | null> {
  const raw = await kv.get(KV_KEY);
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as BootRequestRecord;
    if (!parsed.requestId || !parsed.expiresAt) return null;
    return normalizeRecord({
      ...parsed,
      action: parsed.action ?? "start",
    });
  } catch {
    return null;
  }
}

export async function createBootRequest(
  kv: KVNamespace,
  ttlSeconds: number,
  action: BootRequestAction = "start"
): Promise<BootRequestRecord> {
  const createdAt = nowIso();
  const expiresAt = new Date(Date.now() + ttlSeconds * 1000).toISOString();
  const record: BootRequestRecord = {
    requestId: crypto.randomUUID(),
    createdAt,
    expiresAt,
    status: "pending",
    action,
  };
  await kv.put(KV_KEY, JSON.stringify(record), { expirationTtl: ttlSeconds });
  return record;
}

export function toPeekResponse(record: BootRequestRecord | null): BootRequestPeek {
  if (!record || record.status !== "pending") {
    return { pending: false, status: record?.status ?? undefined };
  }
  return {
    pending: true,
    requestId: record.requestId,
    expiresAt: record.expiresAt,
    status: record.status,
    action: record.action ?? "start",
  };
}

export async function peekBootRequest(kv: KVNamespace): Promise<BootRequestPeek> {
  const record = await readBootRequest(kv);
  if (record?.status === "expired") {
    await kv.delete(KV_KEY);
  }
  return toPeekResponse(record);
}

export async function consumeBootRequest(
  kv: KVNamespace,
  requestId?: string
): Promise<{ consumed: boolean; peek: BootRequestPeek }> {
  const record = await readBootRequest(kv);
  if (!record || record.status !== "pending") {
    if (record?.status === "expired") {
      await kv.delete(KV_KEY);
    }
    return { consumed: false, peek: toPeekResponse(record) };
  }

  if (requestId && requestId !== record.requestId) {
    return { consumed: false, peek: toPeekResponse(record) };
  }

  const consumed: BootRequestRecord = {
    ...record,
    status: "consumed",
  };
  await kv.put(KV_KEY, JSON.stringify(consumed), {
    expirationTtl: bootRequestRemainingTtl(consumed),
  });

  return {
    consumed: true,
    peek: { pending: false, status: "consumed", requestId: consumed.requestId },
  };
}

function bootRequestRemainingTtl(record: BootRequestRecord): number {
  const remainingMs = Date.parse(record.expiresAt) - Date.now();
  return Math.max(60, Math.ceil(remainingMs / 1000));
}
