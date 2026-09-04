"use client";

import { useMemo } from "react";
import ReactMarkdown, { defaultUrlTransform } from "react-markdown";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";
import rehypeHighlight from "rehype-highlight";
import rehypeKatex from "rehype-katex";
import rehypeSanitize from "rehype-sanitize";
import { markdownComponents } from "@/components/markdown/markdown-components";
import { convertMarkdownTablesToLists } from "@/components/markdown/convert-tables-to-lists";
import { normalizeMathMarkdown } from "@/components/markdown/normalize-math-markdown";
import { markdownSanitizeSchema } from "@/components/markdown/sanitize-schema";
import { stabilizeStreamingMarkdown } from "@/components/markdown/stabilize-streaming";
import { cn } from "@/lib/utils/cn";
import "highlight.js/styles/github-dark.css";
import "katex/dist/katex.min.css";

export interface MarkdownRendererProps {
  content: string;
  /** When true, closes incomplete structures to keep layout stable. */
  streaming?: boolean;
  className?: string;
}

function safeUrlTransform(url: string): string {
  const trimmed = url.trim();
  const lower = trimmed.toLowerCase();
  if (
    lower.startsWith("javascript:") ||
    lower.startsWith("vbscript:") ||
    lower.startsWith("data:text/html")
  ) {
    return "";
  }
  return defaultUrlTransform(url);
}

export function MarkdownRenderer({
  content,
  streaming = false,
  className,
}: MarkdownRendererProps) {
  const prepared = useMemo(() => {
    const source = normalizeMathMarkdown(content ?? "");
    const stabilized = streaming ? stabilizeStreamingMarkdown(source) : source;
    return convertMarkdownTablesToLists(stabilized);
  }, [content, streaming]);

  return (
    <div
      className={cn(
        "markdown-body min-w-0 max-w-none break-words text-[0.9375rem] leading-relaxed",
        className
      )}
    >
      <ReactMarkdown
        remarkPlugins={[remarkGfm, remarkMath]}
        rehypePlugins={[
          rehypeHighlight,
          rehypeKatex,
          [rehypeSanitize, markdownSanitizeSchema],
        ]}
        components={markdownComponents}
        skipHtml
        urlTransform={safeUrlTransform}
      >
        {prepared}
      </ReactMarkdown>
    </div>
  );
}
