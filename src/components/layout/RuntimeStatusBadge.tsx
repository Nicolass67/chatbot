"use client";

import type {
  ModelRuntimeSnapshot,
  RuntimeStatus,
} from "@/lib/runtime/types";
import { Badge } from "@/components/ui/Badge";
import { shortModelName } from "@/lib/models/display-name";
import { cn } from "@/lib/utils/cn";

const statusLabels: Record<RuntimeStatus, string> = {
  OFFLINE: "Hors ligne",
  STARTING: "Démarrage…",
  BOOTING_SERVICES: "Init…",
  LOADING_MODEL: "Chargement",
  READY: "Prête",
  BUSY: "Génération",
  STOPPING: "Arrêt…",
  ERROR: "Erreur",
};

const statusVariant: Record<
  RuntimeStatus,
  "muted" | "warning" | "success" | "accent" | "error"
> = {
  OFFLINE: "muted",
  STARTING: "warning",
  BOOTING_SERVICES: "warning",
  LOADING_MODEL: "warning",
  READY: "success",
  BUSY: "accent",
  STOPPING: "muted",
  ERROR: "error",
};

interface RuntimeStatusBadgeProps {
  status: RuntimeStatus;
  model?: ModelRuntimeSnapshot;
  modelLabel?: string;
  className?: string;
}

export function RuntimeStatusBadge({
  status,
  model,
  modelLabel,
  className,
}: RuntimeStatusBadgeProps) {
  const displayMessage =
    model?.message ??
    (status === "LOADING_MODEL" && model?.targetModel
      ? shortModelName(model.targetModel)
      : undefined);

  const loadedName =
    modelLabel ??
    shortModelName(model?.loadedModel) ??
    shortModelName(model?.preferredModel);

  const showProgress =
    model?.progress !== undefined && model.progress >= 0;

  const showIndeterminate =
    model &&
    (model.phase === "loading" || model.phase === "unloading") &&
    model.progress === undefined;

  return (
    <div className={cn("flex flex-col items-end gap-1", className)}>
      <Badge variant={statusVariant[status]} dot>
        {displayMessage ?? statusLabels[status]}
      </Badge>

      {loadedName && status === "READY" && (
        <span
          className="max-w-[9rem] truncate text-[10px] text-muted-foreground md:max-w-[12rem]"
          title={loadedName}
        >
          {shortModelName(loadedName) ?? loadedName}
        </span>
      )}

      {(model?.pendingRequestCount ?? 0) > 0 &&
        (model?.phase === "loading" || model?.phase === "unloading") && (
          <span className="text-[10px] text-warning">En attente…</span>
        )}

      {showIndeterminate && (
        <div className="h-0.5 w-20 overflow-hidden rounded-full bg-surface-active">
          <div className="h-full w-1/3 animate-[activity-shimmer_1.5s_ease-in-out_infinite] rounded-full bg-warning" />
        </div>
      )}

      {showProgress && (
        <div className="flex w-20 flex-col gap-0.5">
          <div className="h-0.5 overflow-hidden rounded-full bg-surface-active">
            <div
              className="h-full rounded-full bg-warning transition-[width] duration-[var(--duration-normal)]"
              style={{ width: `${Math.min(100, model.progress ?? 0)}%` }}
            />
          </div>
        </div>
      )}

      {model?.phase === "error" && model.error && (
        <span className="max-w-[160px] truncate text-[10px] text-error">
          {model.error}
        </span>
      )}
    </div>
  );
}
