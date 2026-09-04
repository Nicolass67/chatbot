"use client";

import { cn } from "@/lib/utils/cn";

interface ChatEmptyStateProps {
  chatMode?: "chat" | "agent";
  className?: string;
}

export function ChatEmptyState({ chatMode = "chat", className }: ChatEmptyStateProps) {
  return (
    <div
      className={cn(
        "flex flex-col justify-end px-1 pb-8 pt-6 min-h-[40vh]",
        className
      )}
    >
      <h2 className="text-[17px] font-semibold tracking-[-0.02em] text-foreground">
        {chatMode === "agent" ? "Mode Agent" : "Nouvelle conversation"}
      </h2>
      <p className="mt-1.5 max-w-sm text-[13px] leading-relaxed text-muted">
        {chatMode === "agent"
          ? "L’agent planifie, recherche et synthétise une réponse structurée."
          : "Écrivez ci-dessous pour commencer."}
      </p>
    </div>
  );
}
