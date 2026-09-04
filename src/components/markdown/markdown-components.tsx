import type { Components } from "react-markdown";
import { CodeBlock } from "@/components/markdown/CodeBlock";
import { MarkdownExternalLink } from "@/components/markdown/MarkdownExternalLink";
import { cn } from "@/lib/utils/cn";

export const markdownComponents: Components = {
  pre({ children }) {
    return <>{children}</>;
  },
  code({ className, children, ...props }) {
    const match = /language-([\w-]+)/.exec(className ?? "");
    if (match) {
      return (
        <CodeBlock language={match[1]} className={className}>
          {children}
        </CodeBlock>
      );
    }

    return (
      <code
        className="rounded bg-surface px-1.5 py-0.5 font-mono text-[0.875em] text-accent/90 before:content-none after:content-none"
        {...props}
      >
        {children}
      </code>
    );
  },
  a({ href, children }) {
    return (
      <MarkdownExternalLink
        href={href}
        className="break-words text-accent underline decoration-accent/40 underline-offset-2 hover:decoration-accent"
      >
        {children}
      </MarkdownExternalLink>
    );
  },
  table({ children }) {
    return (
      <div className="not-prose my-4 min-w-0 overflow-x-auto rounded-lg border border-border">
        <table className="w-full min-w-max border-collapse text-sm">{children}</table>
      </div>
    );
  },
  thead({ children }) {
    return <thead className="bg-surface">{children}</thead>;
  },
  th({ children, ...props }) {
    return (
      <th
        className="border border-border px-3 py-2 text-left text-xs font-semibold uppercase tracking-wide text-muted"
        {...props}
      >
        {children}
      </th>
    );
  },
  td({ children, ...props }) {
    return (
      <td className="border border-border px-3 py-2 align-top" {...props}>
        {children}
      </td>
    );
  },
  tr({ children, ...props }) {
    return (
      <tr className="even:bg-surface/40" {...props}>
        {children}
      </tr>
    );
  },
  blockquote({ children, ...props }) {
    return (
      <blockquote
        className="border-l-4 border-accent/50 pl-4 italic text-muted [&>p]:my-1"
        {...props}
      >
        {children}
      </blockquote>
    );
  },
  hr() {
    return <hr className="my-6 border-border" />;
  },
  h1({ children, ...props }) {
    return (
      <h1 className="mb-3 mt-6 text-2xl font-bold tracking-tight first:mt-0" {...props}>
        {children}
      </h1>
    );
  },
  h2({ children, ...props }) {
    return (
      <h2 className="mb-2 mt-5 text-xl font-semibold tracking-tight first:mt-0" {...props}>
        {children}
      </h2>
    );
  },
  h3({ children, ...props }) {
    return (
      <h3 className="mb-2 mt-4 text-lg font-semibold first:mt-0" {...props}>
        {children}
      </h3>
    );
  },
  ul({ children, ...props }) {
    return (
      <ul className="my-3 list-disc space-y-1 pl-6 marker:text-muted" {...props}>
        {children}
      </ul>
    );
  },
  ol({ children, ...props }) {
    return (
      <ol className="my-3 list-decimal space-y-1 pl-6 marker:text-muted" {...props}>
        {children}
      </ol>
    );
  },
  li({ children, className, ...props }) {
    return (
      <li className={cn("leading-relaxed", className)} {...props}>
        {children}
      </li>
    );
  },
  p({ children, ...props }) {
    return (
      <p className="my-3 leading-relaxed first:mt-0 last:mb-0" {...props}>
        {children}
      </p>
    );
  },
};
