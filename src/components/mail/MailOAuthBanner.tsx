"use client";

import Link from "next/link";
import { X } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { cn } from "@/lib/utils/cn";
import type { OAuthAccountPublic } from "@/lib/integrations/oauth/types";
import { GMAIL_TRASH_REQUIRED_SCOPES, hasRequiredOAuthScopes } from "@/lib/policy/scopes";

interface MailOAuthBannerProps {
  accounts: OAuthAccountPublic[];
  className?: string;
  onDismiss?: () => void;
}

export function MailOAuthBanner({
  accounts,
  className,
  onDismiss,
}: MailOAuthBannerProps) {
  const connected = accounts.length > 0;
  const account = accounts[0];
  const needsTrashScope =
    connected &&
    account &&
    !hasRequiredOAuthScopes(account.scopes, GMAIL_TRASH_REQUIRED_SCOPES);

  if (connected && !needsTrashScope) return null;

  return (
    <div
      className={cn(
        "flex flex-wrap items-center gap-3 border-b border-border-subtle px-4 py-2.5",
        needsTrashScope && "border-warning/30 bg-warning-muted/40",
        className
      )}
      role="status"
    >
      <p className="min-w-0 flex-1 text-[13px] text-muted">
        {needsTrashScope ? (
          <>
            Gmail est connecté ({account?.accountEmail}). La permission{" "}
            <strong className="font-medium text-foreground">Corbeille</strong>{" "}
            est absente — reconnectez pour supprimer des messages depuis
            l&apos;assistant (optionnel).
          </>
        ) : (
          "Connectez Gmail pour accéder à votre boîte mail."
        )}
      </p>
      <div className="flex items-center gap-2">
        <Link href="/settings/email">
          <Button variant={needsTrashScope ? "secondary" : "primary"} size="sm">
            {needsTrashScope ? "Ajouter la permission Corbeille" : "Connecter Gmail"}
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
