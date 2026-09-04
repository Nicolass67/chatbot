"use client";

import { Cpu } from "lucide-react";
import { Dropdown } from "@/components/ui/Dropdown";
import {
  formatModelCompactName,
  formatModelFullName,
} from "@/lib/models/display-name";

export interface ModelOption {
  id: string;
  label: string;
}

interface ModelSelectorProps {
  models: ModelOption[];
  value: string;
  disabled?: boolean;
  loading?: boolean;
  switching?: boolean;
  switchingLabel?: string;
  onChange: (modelId: string) => void;
  className?: string;
  placement?: "top" | "bottom";
}

export function ModelSelector({
  models,
  value,
  disabled,
  loading,
  switching,
  switchingLabel,
  onChange,
  className,
  placement = "top",
}: ModelSelectorProps) {
  const active = models.find((m) => m.id === value);
  const sourceLabel = active?.label || active?.id || value;
  const compact = formatModelCompactName(sourceLabel, 24);
  const full = formatModelFullName(sourceLabel) || sourceLabel;

  // Pendant un switch : garder le nom du modèle (le statut est dans HeaderStatusCluster)
  const showLoading = Boolean(loading) && !switching;

  return (
    <Dropdown
      label="Modèle"
      value={value}
      options={models.map((m) => {
        const name = m.label || m.id;
        return {
          value: m.id,
          label: formatModelFullName(name) || name,
          description:
            formatModelCompactName(name, 24) !==
            (formatModelFullName(name) || name)
              ? m.id
              : undefined,
        };
      })}
      onChange={onChange}
      disabled={disabled || switching}
      loading={showLoading}
      loadingLabel="…"
      triggerLabel={compact || "Modèle"}
      triggerTitle={
        switching
          ? switchingLabel || full || "Chargement du modèle…"
          : full
      }
      wrapOptions
      icon={<Cpu className="h-3.5 w-3.5 shrink-0 text-muted" strokeWidth={1.75} />}
      triggerClassName="max-w-[min(100%,10.5rem)] sm:max-w-[12rem] md:max-w-[14rem]"
      placement={placement}
      align="end"
      className={className}
    />
  );
}
