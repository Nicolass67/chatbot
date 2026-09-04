"use client";

import Link from "next/link";
import { ArrowRight, FolderOpen } from "lucide-react";
import { Button } from "@/components/ui/Button";
import type { FileIntent } from "@/lib/request-router/types";
import { resolveFilesHandoffHref } from "@/lib/files/handoff";
import { cn } from "@/lib/utils/cn";

export interface FilesHandoffInfo {
  intent: FileIntent;
  reason: string;
  query?: string;
  rootId?: string;
  /** @deprecated optionnel — dérivé côté Web si absent */
  url?: string;
}

interface FilesHandoffCardProps {
  handoff: FilesHandoffInfo;
  className?: string;
}

export function FilesHandoffCard({ handoff, className }: FilesHandoffCardProps) {
  const href =
    handoff.url?.startsWith("/files")
      ? handoff.url
      : resolveFilesHandoffHref(handoff);

  return (
    <div
      className={cn(
        "mb-3 flex flex-wrap items-center gap-3 border-l-2 border-border-strong bg-surface/40 px-4 py-3",
        className
      )}
    >
      <FolderOpen className="h-4 w-4 shrink-0 text-accent" />
      <p className="min-w-0 flex-1 text-sm text-foreground">{handoff.reason}</p>
      <Link href={href}>
        <Button variant="primary" size="sm">
          Ouvrir Files
          <ArrowRight className="h-3.5 w-3.5" />
        </Button>
      </Link>
    </div>
  );
}
