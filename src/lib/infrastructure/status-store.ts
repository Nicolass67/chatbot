import fs from "node:fs";
import path from "node:path";
import type {
  IncidentRecord,
  InfrastructureStatus,
  RepairResult,
} from "./types";

export function supervisorDataDir(root = process.cwd()): string {
  return path.join(root, "data", "supervisor");
}

export function statusFilePath(root = process.cwd()): string {
  return path.join(supervisorDataDir(root), "status.json");
}

export function incidentsFilePath(root = process.cwd()): string {
  return path.join(supervisorDataDir(root), "incidents.json");
}

export function commandFilePath(root = process.cwd()): string {
  return path.join(supervisorDataDir(root), "command.json");
}

function ensureDir(dir: string) {
  fs.mkdirSync(dir, { recursive: true });
}

function atomicWrite(file: string, data: unknown) {
  ensureDir(path.dirname(file));
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2), "utf8");
  fs.renameSync(tmp, file);
}

export function writeInfrastructureStatus(
  status: InfrastructureStatus,
  root = process.cwd()
): void {
  atomicWrite(statusFilePath(root), status);
}

export function readInfrastructureStatus(
  root = process.cwd()
): InfrastructureStatus | null {
  const file = statusFilePath(root);
  try {
    if (!fs.existsSync(file)) return null;
    const raw = fs.readFileSync(file, "utf8");
    if (!raw.trim()) return null;
    return JSON.parse(raw) as InfrastructureStatus;
  } catch {
    return null;
  }
}

export function readIncidents(root = process.cwd()): IncidentRecord[] {
  const file = incidentsFilePath(root);
  try {
    if (!fs.existsSync(file)) return [];
    return JSON.parse(fs.readFileSync(file, "utf8")) as IncidentRecord[];
  } catch {
    return [];
  }
}

export function appendIncident(
  incident: IncidentRecord,
  root = process.cwd(),
  keep = 100
): void {
  const list = readIncidents(root);
  list.unshift(incident);
  atomicWrite(incidentsFilePath(root), list.slice(0, keep));
}

export function writeRepairResult(
  result: RepairResult,
  root = process.cwd()
): void {
  atomicWrite(path.join(supervisorDataDir(root), "last-repair.json"), result);
}

export function readLastRepair(root = process.cwd()): RepairResult | null {
  const file = path.join(supervisorDataDir(root), "last-repair.json");
  try {
    if (!fs.existsSync(file)) return null;
    return JSON.parse(fs.readFileSync(file, "utf8")) as RepairResult;
  } catch {
    return null;
  }
}

export type SupervisorCommandPayload = {
  type: "diagnose" | "repair" | "repair_service" | "restart_service";
  serviceId?: string;
  requestId: string;
  requestedAt: string;
};

export function enqueueSupervisorCommand(
  cmd: Omit<SupervisorCommandPayload, "requestedAt">,
  root = process.cwd()
): void {
  atomicWrite(commandFilePath(root), {
    ...cmd,
    requestedAt: new Date().toISOString(),
  } satisfies SupervisorCommandPayload);
}

export function consumeSupervisorCommand(
  root = process.cwd()
): SupervisorCommandPayload | null {
  const file = commandFilePath(root);
  try {
    if (!fs.existsSync(file)) return null;
    const raw = fs.readFileSync(file, "utf8");
    fs.unlinkSync(file);
    return JSON.parse(raw) as SupervisorCommandPayload;
  } catch {
    return null;
  }
}

export function emptyInfrastructureStatus(
  message = "Supervisor non démarré"
): InfrastructureStatus {
  return {
    overallState: "offline",
    powerState: "unknown",
    generatedAt: new Date().toISOString(),
    supervisorAlive: false,
    message,
    services: [],
    activeRepairId: null,
  };
}
