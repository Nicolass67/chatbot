"use client";

import { Bot, MessageCircle } from "lucide-react";
import type { ChatMode } from "@/lib/agent/types";
import { getModeLabel } from "@/lib/agent/config";
import { Dropdown } from "@/components/ui/Dropdown";

interface ModeSelectorProps {
  value: ChatMode;
  disabled?: boolean;
  onChange: (mode: ChatMode) => void;
  className?: string;
}

const MODES: ChatMode[] = ["chat", "agent"];

const modeIcons: Record<ChatMode, typeof MessageCircle> = {
  chat: MessageCircle,
  agent: Bot,
};

export function ModeSelector({
  value,
  disabled,
  onChange,
  className,
}: ModeSelectorProps) {
  const Icon = modeIcons[value];

  return (
    <Dropdown
      label="Mode"
      value={value}
      options={MODES.map((mode) => ({
        value: mode,
        label: getModeLabel(mode),
        description:
          mode === "agent"
            ? "Planification et recherche multi-étapes"
            : "Conversation directe",
      }))}
      onChange={onChange}
      disabled={disabled}
      icon={<Icon className="h-3.5 w-3.5 shrink-0 text-accent" strokeWidth={1.75} />}
      className={className}
    />
  );
}
