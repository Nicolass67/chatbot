"use client";

import { Badge } from "@/components/ui/Badge";
import { cn } from "@/lib/utils/cn";

export type WebRuntimeStatus =
  | "connected"
  | "starting"
  | "unavailable"
  | "disabled";

const statusLabels: Record<WebRuntimeStatus, string> = {
  connected: "Web",
  starting: "Web…",
  unavailable: "Web off",
  disabled: "Web off",
};

const statusVariant: Record<
  WebRuntimeStatus,
  "success" | "warning" | "error" | "muted"
> = {
  connected: "success",
  starting: "warning",
  unavailable: "error",
  disabled: "muted",
};

interface WebStatusBadgeProps {
  status: WebRuntimeStatus;
  message?: string;
  className?: string;
}

export function WebStatusBadge({
  status,
  message,
  className,
}: WebStatusBadgeProps) {
  return (
    <div className={cn("flex flex-col items-end gap-0.5", className)}>
      <Badge variant={statusVariant[status]} dot>
        <span title={message}>{statusLabels[status]}</span>
      </Badge>
      {message && status !== "connected" && (
        <span className="max-w-[140px] truncate text-[10px] text-muted-foreground">
          {message}
        </span>
      )}
    </div>
  );
}
