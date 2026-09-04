"use client";

import { useState, type MouseEvent } from "react";
import { ChevronDown, ExternalLink, Globe } from "lucide-react";
import type { SearchResult } from "@/lib/tools/types";
import { domainInitial, faviconUrl } from "@/components/chat/source-utils";
import { openExternal } from "@/lib/native/open-external";
import { cn } from "@/lib/utils/cn";

interface SourceCitationsProps {
  sources: SearchResult[];
  className?: string;
}

function SourceFavicon({ domain }: { domain: string }) {
  const [failed, setFailed] = useState(false);

  if (failed) {
    return (
      <span className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-surface-hover text-[9px] font-semibold text-muted">
        {domainInitial(domain)}
      </span>
    );
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={faviconUrl(domain)}
      alt=""
      width={16}
      height={16}
      className="h-4 w-4 shrink-0 rounded-sm"
      onError={() => setFailed(true)}
    />
  );
}

function SourcePill({
  source,
  compact = false,
}: {
  source: SearchResult;
  compact?: boolean;
}) {
  const onClick = (event: MouseEvent<HTMLAnchorElement>) => {
    event.preventDefault();
    void openExternal(source.url);
  };

  return (
    <a
      href={source.url}
      target="_blank"
      rel="noopener noreferrer"
      title={source.title}
      onClick={onClick}
      className={cn(
        "inline-flex max-w-[160px] items-center gap-1.5 rounded-[var(--radius-sm)] px-1.5 py-0.5 text-xs text-muted transition-colors hover:bg-surface-hover hover:text-foreground",
        compact && "max-w-[120px]"
      )}
    >
      <SourceFavicon domain={source.domain} />
      <span className="truncate">{source.domain}</span>
    </a>
  );
}

export function SourceCitations({ sources, className }: SourceCitationsProps) {
  const [expanded, setExpanded] = useState(false);

  if (sources.length === 0) return null;

  const preview = sources.slice(0, 4);
  const extra = sources.length - preview.length;

  return (
    <div className={cn("mb-3", className)}>
      <button
        type="button"
        onClick={() => setExpanded((o) => !o)}
        className="group flex w-full items-center gap-2 rounded-lg text-left transition-colors hover:bg-surface/40"
        aria-expanded={expanded}
      >
        <Globe className="h-3.5 w-3.5 shrink-0 text-muted" />
        <span className="text-xs font-medium text-muted">
          Sources
        </span>
        <div className="flex min-w-0 flex-1 flex-wrap items-center gap-1.5">
          {!expanded &&
            preview.map((source) => (
              <span
                key={source.url}
                onClick={(e) => e.stopPropagation()}
                onKeyDown={(e) => e.stopPropagation()}
              >
                <SourcePill source={source} compact />
              </span>
            ))}
          {!expanded && extra > 0 && (
            <span className="rounded-full bg-surface px-2 py-0.5 text-[10px] text-muted">
              +{extra}
            </span>
          )}
        </div>
        <ChevronDown
          className={cn(
            "h-3.5 w-3.5 shrink-0 text-muted transition-transform group-hover:text-foreground",
            expanded && "rotate-180"
          )}
        />
      </button>

      {expanded && (
        <div className="mt-2 grid gap-2 sm:grid-cols-2">
          {sources.map((source, index) => (
            <a
              key={source.url}
              href={source.url}
              target="_blank"
              rel="noopener noreferrer"
              onClick={(event) => {
                event.preventDefault();
                void openExternal(source.url);
              }}
              className="flex gap-2.5 rounded-xl border border-border/70 bg-surface/50 p-3 transition-colors hover:border-accent/30 hover:bg-surface"
            >
              <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-background/80">
                <SourceFavicon domain={source.domain} />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-start gap-1">
                  <p className="line-clamp-2 flex-1 text-sm font-medium leading-snug text-foreground">
                    {source.title}
                  </p>
                  <ExternalLink className="mt-0.5 h-3 w-3 shrink-0 text-muted" />
                </div>
                <p className="mt-0.5 truncate text-[11px] text-muted">
                  {index + 1}. {source.domain}
                </p>
                {source.snippet && (
                  <p className="mt-1 line-clamp-2 text-xs leading-relaxed text-muted">
                    {source.snippet}
                  </p>
                )}
              </div>
            </a>
          ))}
        </div>
      )}
    </div>
  );
}

/** @deprecated Use SourceCitations */
export { SourceCitations as SourcesList };
