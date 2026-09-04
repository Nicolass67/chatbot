"use client";

import type { ReactNode } from "react";
import { AssistantFabShell } from "@/components/ui/AssistantFabShell";

interface FilesAssistantFabProps {
  open: boolean;
  onOpen: () => void;
  onClose: () => void;
  children: ReactNode;
}

/**
 * Pastille bas-droite → panneau assistant Files (tous viewports).
 * keepMounted : conserve l’historique de discussion quand le panneau est fermé.
 */
export function FilesAssistantFab({
  open,
  onOpen,
  onClose,
  children,
}: FilesAssistantFabProps) {
  return (
    <AssistantFabShell
      open={open}
      onOpen={onOpen}
      onClose={onClose}
      title="Assistant Files"
      openLabel="Ouvrir l'assistant Files"
      keepMounted
    >
      {children}
    </AssistantFabShell>
  );
}
