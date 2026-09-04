"use client";

import type { ReactNode } from "react";
import { AssistantFabShell } from "@/components/ui/AssistantFabShell";

interface MailAssistantFabProps {
  open: boolean;
  onOpen: () => void;
  onClose: () => void;
  children: ReactNode;
}

/**
 * Pastille bas-droite → panneau assistant Mail (tous viewports).
 */
export function MailAssistantFab({
  open,
  onOpen,
  onClose,
  children,
}: MailAssistantFabProps) {
  return (
    <AssistantFabShell
      open={open}
      onOpen={onOpen}
      onClose={onClose}
      title="Assistant"
      openLabel="Ouvrir l'assistant mail"
    >
      {children}
    </AssistantFabShell>
  );
}
