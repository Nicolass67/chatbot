"use client";

import Link from "next/link";
import { ArrowRight, Mail } from "lucide-react";
import { Button } from "@/components/ui/Button";
import type { EmailIntent } from "@/lib/request-router/types";
import { resolveMailHandoffHref } from "@/lib/mail/handoff";
import { cn } from "@/lib/utils/cn";

export interface MailHandoffInfo {
  intent: EmailIntent;
  reason: string;
  query?: string;
  threadId?: string;
  label?: string;
  /** @deprecated optionnel — dérivé côté Web si absent */
  url?: string;
}

interface MailHandoffCardProps {
  handoff: MailHandoffInfo;
  className?: string;
}

export function MailHandoffCard({ handoff, className }: MailHandoffCardProps) {
  const href =
    handoff.url?.startsWith("/mail")
      ? handoff.url
      : resolveMailHandoffHref(handoff);

  return (
    <div
      className={cn(
        "mb-3 flex flex-wrap items-center gap-3 border-l-2 border-border-strong bg-surface/40 px-4 py-3",
        className
      )}
    >
      <Mail className="h-4 w-4 shrink-0 text-accent" />
      <p className="min-w-0 flex-1 text-sm text-foreground">{handoff.reason}</p>
      <Link href={href}>
        <Button variant="primary" size="sm">
          Ouvrir Mail
          <ArrowRight className="h-3.5 w-3.5" />
        </Button>
      </Link>
    </div>
  );
}
