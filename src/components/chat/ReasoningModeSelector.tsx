"use client";

import { useEffect, useState } from "react";
import { Brain } from "lucide-react";
import type { ReasoningCapabilities } from "@/lib/runtime/reasoning-types";
import { getReasoningModeLabel } from "@/lib/runtime/reasoning-types";
import { Dropdown } from "@/components/ui/Dropdown";
import { cn } from "@/lib/utils/cn";

interface ReasoningModeSelectorProps {
  modelId: string;
  value: string | null;
  disabled?: boolean;
  onChange: (modeId: string) => void;
  className?: string;
}

export function ReasoningModeSelector({
  modelId,
  value,
  disabled,
  onChange,
  className,
}: ReasoningModeSelectorProps) {
  const [caps, setCaps] = useState<ReasoningCapabilities | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!modelId) {
      setCaps(null);
      return;
    }
    setLoading(true);
    fetch(`/api/runtime/reasoning-capabilities?model=${encodeURIComponent(modelId)}`)
      .then(async (r) => (await r.json()) as ReasoningCapabilities)
      .then((data) => setCaps(data))
      .catch(() =>
        setCaps({
          modelId,
          supported: false,
          kind: "none",
          modes: [],
          defaultModeId: null,
          transmissionMethod: null,
          source: "unknown",
          limitations: "Capacité non détectée.",
        })
      )
      .finally(() => setLoading(false));
  }, [modelId]);

  const resolvedValue =
    caps?.supported && caps.modes.length > 0
      ? (value && caps.modes.some((m) => m.id === value) ? value : null) ??
        (caps.modes.find((m) => m.id === "off")?.id ?? caps.modes[0]?.id ?? null)
      : null;

  useEffect(() => {
    if (loading || !resolvedValue || value === resolvedValue) return;
    onChange(resolvedValue);
  }, [loading, resolvedValue, value, onChange]);

  if (!modelId) {
    return (
      <span className={cn("px-2 text-[11px] text-muted-foreground", className)}>
        Raisonnement —
      </span>
    );
  }

  if (loading) {
    return (
      <span className={cn("px-2 text-[11px] text-muted-foreground", className)}>
        Raisonnement…
      </span>
    );
  }

  if (!caps?.supported || caps.modes.length === 0) {
    return (
      <span className={cn("text-[11px] text-muted-foreground", className)}>
        Raisonnement indisponible
      </span>
    );
  }

  return (
    <Dropdown
      label="Raisonnement"
      value={resolvedValue ?? caps.modes[0].id}
      options={caps.modes.map((mode) => ({
        value: mode.id,
        label: mode.label ?? getReasoningModeLabel(mode.id),
      }))}
      onChange={onChange}
      disabled={disabled}
      icon={<Brain className="h-3.5 w-3.5 shrink-0 text-muted" strokeWidth={1.75} />}
      className={className}
    />
  );
}
