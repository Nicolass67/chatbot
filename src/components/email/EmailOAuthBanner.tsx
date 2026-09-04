"use client";

import Link from "next/link";
import { Mail, X } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { cn } from "@/lib/utils/cn";

interface EmailOAuthBannerProps {
  visible: boolean;
  onDismiss?: () => void;
  className?: string;
}

export function EmailOAuthBanner({
  visible,
  onDismiss,
  className,
}: EmailOAuthBannerProps) {
  if (!visible) return null;

  return (
    <div
      className={cn(
        "mx-4 mb-2 flex flex-wrap items-center gap-3 rounded-[var(--radius-xl)] border border-accent/30 bg-accent-muted/40 px-4 py-3",
        className
      )}
      role="status"
    >
      <Mail className="h-4 w-4 shrink-0 text-accent" />
      <p className="min-w-0 flex-1 text-sm text-foreground">
        Connectez Gmail pour lire et envoyer des emails depuis le chat.
      </p>
      <div className="flex items-center gap-2">
        <Link href="/settings/email">
          <Button variant="primary" size="sm">
            Connecter Gmail
          </Button>
        </Link>
        {onDismiss && (
          <button
            type="button"
            onClick={onDismiss}
            className="rounded-md p-1 text-muted-foreground transition-colors hover:bg-surface-hover hover:text-foreground"
            aria-label="Masquer"
          >
            <X className="h-4 w-4" />
          </button>
        )}
      </div>
    </div>
  );
}
