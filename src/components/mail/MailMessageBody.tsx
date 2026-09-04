"use client";

import { MailHtmlViewer } from "@/components/mail/MailHtmlViewer";
import {
  collapseLongUrls,
  htmlToPlainText,
  preparePlainTextForDisplay,
  shouldPreferPlainText,
} from "@/lib/mail/html-utils";
import { cn } from "@/lib/utils/cn";

interface MailMessageBodyProps {
  bodyText: string;
  bodyHtml?: string;
  snippet?: string;
}

export function MailMessageBody({
  bodyText,
  bodyHtml,
  snippet,
}: MailMessageBodyProps) {
  const preferPlain = shouldPreferPlainText(bodyText, bodyHtml);

  if (bodyHtml?.trim() && !preferPlain) {
    return <MailHtmlViewer html={bodyHtml} className="min-h-full w-full" />;
  }

  const raw =
    bodyText?.trim() ||
    (bodyHtml ? htmlToPlainText(bodyHtml) : "") ||
    snippet?.trim() ||
    "";
  const display = collapseLongUrls(preparePlainTextForDisplay(raw));

  if (!display) {
    return (
      <p className="text-sm italic text-muted-foreground">(contenu vide)</p>
    );
  }

  return (
    <article
      className={cn(
        "mail-plain-body w-full text-[0.9375rem] leading-[1.65] text-foreground",
        "whitespace-pre-wrap break-words"
      )}
    >
      {display}
    </article>
  );
}
