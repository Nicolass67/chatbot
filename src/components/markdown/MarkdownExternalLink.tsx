"use client";

import type { MouseEvent, ReactNode } from "react";
import {
  isExternalHttpUrl,
  openExternal,
} from "@/lib/native/open-external";

interface MarkdownExternalLinkProps {
  href?: string;
  children?: ReactNode;
  className?: string;
}

/** Lien markdown : externes → Browser/window.open ; internes → navigation normale. */
export function MarkdownExternalLink({
  href,
  children,
  className,
}: MarkdownExternalLinkProps) {
  const onClick = (event: MouseEvent<HTMLAnchorElement>) => {
    if (!href || !isExternalHttpUrl(href)) return;
    event.preventDefault();
    void openExternal(href);
  };

  return (
    <a
      href={href}
      target="_blank"
      rel="noopener noreferrer nofollow"
      className={className}
      onClick={onClick}
    >
      {children}
    </a>
  );
}
