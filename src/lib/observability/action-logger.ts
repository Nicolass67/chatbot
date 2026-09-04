import { safeActionMetadata } from "./redact";

export interface ActionAuditLogEvent {
  userId: string;
  actionType: string;
  resourceType: string;
  resourceId: string;
  status: string;
  metadata?: Record<string, unknown>;
}

/** Log structuré JSON — métadonnées redacted (pas de tokens OAuth / confirmation). */
export function logActionAudit(event: ActionAuditLogEvent): void {
  const payload = {
    type: "action_audit",
    ts: new Date().toISOString(),
    userId: event.userId,
    actionType: event.actionType,
    resourceType: event.resourceType,
    resourceId: event.resourceId,
    status: event.status,
    metadata: safeActionMetadata(event.metadata),
  };

  console.info(JSON.stringify(payload));
}
