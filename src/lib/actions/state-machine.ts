import type { ActionStatus } from "./types";

const TERMINAL_STATUSES = new Set<ActionStatus>([
  "completed",
  "rejected",
  "cancelled",
  "expired",
  "failed",
]);

const ALLOWED_TRANSITIONS: Record<ActionStatus, readonly ActionStatus[]> = {
  proposed: ["pending_confirmation", "rejected", "cancelled"],
  pending_confirmation: ["confirmed", "cancelled", "expired", "rejected"],
  confirmed: ["executing", "failed"],
  executing: ["completed", "failed"],
  completed: [],
  rejected: [],
  cancelled: [],
  expired: [],
  failed: [],
};

export function canTransition(
  from: ActionStatus,
  to: ActionStatus
): boolean {
  return ALLOWED_TRANSITIONS[from]?.includes(to) ?? false;
}

export function assertTransition(from: ActionStatus, to: ActionStatus): void {
  if (!canTransition(from, to)) {
    throw new Error(
      `Transition d'action invalide : ${from} → ${to}.`
    );
  }
}

export function isTerminalStatus(status: ActionStatus): boolean {
  return TERMINAL_STATUSES.has(status);
}

export function initialSendActionStatus(): ActionStatus {
  return "pending_confirmation";
}
