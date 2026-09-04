"use client";

import type { ReactNode } from "react";
import { CopyButton } from "@/components/markdown/CopyButton";
import { formatLanguage } from "@/components/markdown/format-language";
import { cn } from "@/lib/utils/cn";

interface CodeBlockProps {
  language: string;
  className?: string;
  children: ReactNode;
}

export function CodeBlock({ language, className, children }: CodeBlockProps) {
  const code = String(children).replace(/\n$/, "");

  return (
    <div className="not-prose my-4 min-w-0 overflow-hidden rounded-lg border border-border-subtle bg-[var(--code-bg)]">
      <div className="flex items-center justify-between gap-2 border-b border-border/80 bg-surface/90 px-3 py-1.5">
        <span className="truncate text-xs font-medium text-muted">
          {formatLanguage(language)}
        </span>
        <CopyButton value={code} />
      </div>
      <div className="overflow-x-auto">
        <pre className="m-0 p-4 text-[0.8125rem] leading-relaxed">
          <code className={cn("hljs font-mono", className)}>{children}</code>
        </pre>
      </div>
    </div>
  );
}
