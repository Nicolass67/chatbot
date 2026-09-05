/**
 * Infrastructure supervision contracts.
 * Process / health / readiness are distinct dimensions.
 */

export type OverallState =
  | "healthy"
  | "degraded"
  | "recovering"
  | "offline"
  | "error";

export type PowerState =
  | "online"
  | "offline"
  | "starting"
  | "stopping"
  | "unknown";

export type ProcessState =
  | "stopped"
  | "starting"
  | "running"
  | "stopping"
  | "unknown";

export type HealthState = "healthy" | "unhealthy" | "unknown";

export type ReadinessState =
  | "ready"
  | "not_ready"
  | "loading"
  | "unknown";

export type ServiceCriticality = "required" | "optional";

export type ServiceCategory =
  | "core"
  | "ai"
  | "search"
  | "ingress"
  | "platform";

export type RepairActionType =
  | "start_service"
  | "stop_service"
  | "restart_service"
  | "start_docker_container"
  | "restart_docker_container"
  | "ensure_docker"
  | "wait_for_health"
  | "wait_for_readiness"
  | "reload_model"
  | "refresh_tunnel";

export type DiagnosisCategory =
  | "process_absent"
  | "health_down"
  | "readiness_false"
  | "container_stopped"
  | "docker_unavailable"
  | "lm_studio_unreachable"
  | "model_not_loaded"
  | "tunnel_disconnected"
  | "dependency_unavailable"
  | "crash_loop"
  | "unknown";

export interface ServiceDefinition {
  id: string;
  displayName: string;
  humanName: string;
  category: ServiceCategory;
  criticality: ServiceCriticality;
  enabled: boolean;
  dependencies: string[];
  optionalDependencies: string[];
  healthIntervalMs: number;
  healthTimeoutMs: number;
  startupTimeoutMs: number;
  failureThreshold: number;
  recoveryThreshold: number;
  maxRestarts: number;
  restartWindowMs: number;
  baseBackoffMs: number;
  maxBackoffMs: number;
}

export interface ServiceStatusSnapshot {
  id: string;
  displayName: string;
  humanName: string;
  category: ServiceCategory;
  criticality: ServiceCriticality;
  process: ProcessState;
  health: HealthState;
  readiness: ReadinessState;
  summary: string;
  lastCheckAt: string | null;
  lastRecoveryAt: string | null;
  restartCount: number;
  incidentId: string | null;
  crashLoop: boolean;
  detail?: Record<string, unknown>;
}

export interface InfrastructureStatus {
  overallState: OverallState;
  powerState: PowerState;
  generatedAt: string;
  supervisorAlive: boolean;
  message: string;
  services: ServiceStatusSnapshot[];
  activeRepairId: string | null;
}

/** Alias used by status-store / API */
export type InfraStatus = InfrastructureStatus;

export interface DiagnosticResult {
  incidentId: string;
  serviceId: string;
  category: DiagnosisCategory;
  severity: "info" | "notice" | "degraded" | "error" | "critical";
  evidence: string[];
  probableCause: string;
  recommendedRepair: RepairActionType[];
  confidence: number;
  timestamp: string;
}

export interface RepairAction {
  type: RepairActionType;
  serviceId: string;
  reason: string;
}

export interface RepairPlan {
  planId: string;
  incidentId: string;
  targetServiceIds: string[];
  untouchedServiceIds: string[];
  actions: RepairAction[];
  diagnosis: DiagnosticResult[];
  createdAt: string;
}

export interface RepairResult {
  planId: string;
  incidentId: string;
  status:
    | "success"
    | "partial"
    | "failed"
    | "already_in_progress"
    | "skipped"
    | "queued";
  actions: Array<{
    type: RepairActionType;
    serviceId: string;
    ok: boolean;
    detail: string;
  }>;
  repairedServices: string[];
  untouchedServices: string[];
  durationMs: number;
  message: string;
}

export interface IncidentRecord {
  id: string;
  serviceId: string;
  detectedAt: string;
  resolvedAt: string | null;
  category: DiagnosisCategory;
  diagnosis: string;
  actions: string[];
  result: "open" | "recovered" | "failed" | "circuit_open";
  restartCount: number;
  durationMs: number | null;
}
