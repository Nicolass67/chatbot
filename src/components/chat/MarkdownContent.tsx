"use client";

import { MarkdownRenderer } from "@/components/markdown";

interface MarkdownContentProps {
  content: string;
  streaming?: boolean;
}

/** @deprecated Prefer MarkdownRenderer directly for new code. */
export function MarkdownContent({ content, streaming }: MarkdownContentProps) {
  return <MarkdownRenderer content={content} streaming={streaming} />;
}
