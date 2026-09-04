"use client";

import type { ReactNode } from "react";
import { cn } from "@/lib/utils/cn";

interface MailSummaryCardProps {
  content: string;
  className?: string;
}

interface SummarySection {
  title: string;
  body: string;
}

function parseSummarySections(content: string): SummarySection[] {
  const normalized = content.replace(/\r\n/g, "\n").trim();
  const parts = normalized.split(/^##\s+/m).filter(Boolean);

  if (parts.length <= 1 && !normalized.startsWith("##")) {
    return [{ title: "Résumé", body: normalized }];
  }

  return parts.map((part) => {
    const lines = part.split("\n");
    const title = (lines[0] ?? "Section").trim();
    const body = lines.slice(1).join("\n").trim();
    return { title, body };
  });
}

function renderBody(body: string) {
  const lines = body.split("\n");
  const nodes: ReactNode[] = [];
  let listItems: string[] = [];

  const flushList = () => {
    if (listItems.length === 0) return;
    nodes.push(
      <ul key={`ul-${nodes.length}`} className="space-y-1.5 pl-1">
        {listItems.map((item, i) => (
          <li
            key={i}
            className="flex gap-2 text-sm leading-relaxed text-foreground/90"
          >
            <span className="mt-2 h-1 w-1 shrink-0 rounded-full bg-muted-foreground" />
            <span>{item}</span>
          </li>
        ))}
      </ul>
    );
    listItems = [];
  };

  for (const line of lines) {
    const bullet = line.match(/^[-*•]\s+(.+)$/);
    if (bullet) {
      listItems.push(bullet[1] ?? "");
      continue;
    }
    flushList();
    if (!line.trim()) continue;
    nodes.push(
      <p
        key={`p-${nodes.length}`}
        className="text-sm leading-relaxed text-foreground/90"
      >
        {line}
      </p>
    );
  }
  flushList();
  return nodes;
}

export function MailSummaryCard({ content, className }: MailSummaryCardProps) {
  const sections = parseSummarySections(content);

  return (
    <article
      className={cn(
        "overflow-hidden border-t border-border-subtle bg-transparent",
        className
      )}
    >
      <div className="border-b border-border-subtle bg-accent-subtle px-3.5 py-2.5">
        <p className="text-xs font-semibold uppercase tracking-wide text-accent">
          Résumé du message
        </p>
      </div>
      <div className="space-y-4 p-3.5">
        {sections.map((section) => (
          <section key={section.title} className="space-y-2">
            <h3 className="text-xs font-semibold uppercase tracking-wide text-muted">
              {section.title}
            </h3>
            <div className="space-y-2">{renderBody(section.body)}</div>
          </section>
        ))}
      </div>
    </article>
  );
}
