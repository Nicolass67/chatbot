"use client";

import type {
  ModelRuntimeSnapshot,
  RuntimeStatus,
} from "@/lib/runtime/types";
import type { WebRuntimeStatus } from "@/components/layout/WebStatusBadge";
import { shortModelName } from "@/lib/models/display-name";
import { cn } from "@/lib/utils/cn";

const webLabels: Record<WebRuntimeStatus, string> = {
  connected: "Web",
  starting: "Web…",
  unavailable: "Web off",
  disabled: "Web off",
};

type StatusTone = "success" | "warning" | "error" | "accent" | "muted";

function isRuntimeActive(status: RuntimeStatus): boolean {
  return status === "READY" || status === "BUSY";
}

function getRuntimeActivityLabel(status: RuntimeStatus): string {
  switch (status) {
    case "READY":
      return "Prêt";
    case "BUSY":
      return "Actif";
    case "LOADING_MODEL":
      return "Chargement";
    case "STARTING":
    case "BOOTING_SERVICES":
      return "Démarrage";
    case "ERROR":
      return "Erreur";
    case "STOPPING":
      return "Arrêt";
    default:
      return "Inactif";
  }
}

function getRuntimeActivityTone(status: RuntimeStatus): StatusTone {
  if (isRuntimeActive(status)) return "success";
  if (
    status === "STARTING" ||
    status === "BOOTING_SERVICES" ||
    status === "LOADING_MODEL"
  ) {
    return "warning";
  }
  if (status === "ERROR") return "error";
  return "muted";
}

const toneDot: Record<StatusTone, string> = {
  success: "bg-success",
  warning: "bg-warning",
  error: "bg-error",
  accent: "bg-accent",
  muted: "bg-muted-foreground",
};

const webTone: Record<WebRuntimeStatus, StatusTone> = {
  connected: "success",
  starting: "warning",
  unavailable: "error",
  disabled: "muted",
};

function StatusItem({
  label,
  tone,
  title,
}: {
  label: string;
  tone: StatusTone;
  title?: string;
}) {
  return (
    <span
      className="inline-flex items-center gap-1.5 whitespace-nowrap"
      title={title}
    >
      <span
        className={cn("h-1.5 w-1.5 shrink-0 rounded-full", toneDot[tone])}
        aria-hidden
      />
      <span className="text-[11px] font-medium leading-none text-foreground">{label}</span>
    </span>
  );
}

function Divider() {
  return <span className="h-3 w-px shrink-0 bg-border-strong/60" aria-hidden />;
}

interface HeaderStatusClusterProps {
  runtimeStatus: RuntimeStatus;
  modelRuntime: ModelRuntimeSnapshot | null;
  activeModelLabel?: string;
  webStatus?: WebRuntimeStatus;
  webStatusMessage?: string;
  /** Affiche l'indicateur Web (défaut: true). Utile de le masquer dans /mail. */
  showWeb?: boolean;
  /** Alignement du bloc (chat header = end, panneaux = start). */
  align?: "start" | "end";
  className?: string;
}

export function HeaderStatusCluster({
  runtimeStatus,
  modelRuntime,
  activeModelLabel,
  webStatus = "disabled",
  webStatusMessage,
  showWeb = true,
  align = "end",
  className,
}: HeaderStatusClusterProps) {
  const runtimeLabel = getRuntimeActivityLabel(runtimeStatus);
  const runtimeActivityTone = getRuntimeActivityTone(runtimeStatus);

  const modelName =
    activeModelLabel ??
    shortModelName(modelRuntime?.targetModel) ??
    shortModelName(modelRuntime?.loadedModel) ??
    shortModelName(modelRuntime?.preferredModel);

  const showModel =
    Boolean(modelName) &&
    (runtimeStatus === "READY" ||
      runtimeStatus === "BUSY" ||
      runtimeStatus === "LOADING_MODEL");

  const showProgress =
    modelRuntime?.progress !== undefined && modelRuntime.progress >= 0;

  const showIndeterminate =
    modelRuntime &&
    (modelRuntime.phase === "loading" || modelRuntime.phase === "unloading") &&
    modelRuntime.progress === undefined;

  const isLoadingModel =
    runtimeStatus === "LOADING_MODEL" ||
    modelRuntime?.phase === "loading" ||
    modelRuntime?.phase === "unloading";

  // Évite de répéter « Chargement de … » sous la pastille + barre de progression
  const detailMessage =
    (modelRuntime?.phase === "error" && modelRuntime.error) ||
    (showWeb &&
    webStatusMessage &&
    webStatus !== "connected"
      ? webStatusMessage
      : undefined) ||
    ((modelRuntime?.pendingRequestCount ?? 0) > 0 &&
    (modelRuntime?.phase === "loading" || modelRuntime?.phase === "unloading")
      ? "Requête en attente du modèle…"
      : undefined) ||
    (isLoadingModel
      ? modelRuntime?.message ?? undefined
      : undefined);

  return (
    <div
      className={cn(
        "flex flex-col gap-1",
        align === "end" ? "items-end" : "items-start",
        className
      )}
    >
      <div
        className="inline-flex max-w-full items-center gap-2.5"
        role="status"
        aria-live="polite"
      >
        {showWeb && (
          <>
            <StatusItem
              label={webLabels[webStatus]}
              tone={webTone[webStatus]}
              title={webStatusMessage}
            />
            <Divider />
          </>
        )}
        <StatusItem
          label={runtimeLabel}
          tone={runtimeActivityTone}
          title={
            modelRuntime?.message ??
            (runtimeStatus === "LOADING_MODEL" && modelRuntime?.targetModel
              ? `Chargement · ${shortModelName(modelRuntime.targetModel)}`
              : runtimeLabel)
          }
        />
        {showModel && (
          <span className="inline-flex items-center gap-2.5">
            <Divider />
            <span
              className="max-w-[10rem] truncate text-[11px] leading-none text-muted"
              title={modelName ?? undefined}
            >
              {shortModelName(modelName) ?? modelName}
            </span>
          </span>
        )}
      </div>

      {(showIndeterminate || showProgress) && (
        <div className="w-[min(140px,40vw)]">
          <div className="h-0.5 overflow-hidden rounded-full bg-surface-active">
            <div
              className={cn(
                "h-full rounded-full bg-warning",
                showIndeterminate
                  ? "w-1/3 animate-[activity-shimmer_1.5s_ease-in-out_infinite]"
                  : "transition-[width] duration-[var(--duration-normal)]"
              )}
              style={
                showProgress
                  ? { width: `${Math.min(100, modelRuntime?.progress ?? 0)}%` }
                  : undefined
              }
            />
          </div>
        </div>
      )}

      {detailMessage && (
        <p className="max-w-[200px] truncate text-[10px] text-muted-foreground">
          {detailMessage}
        </p>
      )}
    </div>
  );
}
