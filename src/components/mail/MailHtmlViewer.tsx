"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { wrapEmailHtmlDocument } from "@/lib/mail/html-utils";
import { cn } from "@/lib/utils/cn";

interface MailHtmlViewerProps {
  html: string;
  className?: string;
}

/**
 * Rendu isolé dans une iframe : le HTML email ne peut plus élargir
 * (ni forcer un zoom arrière sur) la page parente.
 */
export function MailHtmlViewer({ html, className }: MailHtmlViewerProps) {
  const srcDoc = useMemo(() => wrapEmailHtmlDocument(html), [html]);
  const iframeRef = useRef<HTMLIFrameElement>(null);
  const [height, setHeight] = useState(320);

  useEffect(() => {
    const iframe = iframeRef.current;
    if (!iframe) return;

    let ro: ResizeObserver | null = null;
    let cancelled = false;

    const measure = () => {
      if (cancelled) return;
      try {
        const doc = iframe.contentDocument;
        if (!doc?.documentElement) return;
        const body = doc.body;
        const h = Math.max(
          body?.scrollHeight ?? 0,
          body?.offsetHeight ?? 0,
          doc.documentElement.scrollHeight,
          doc.documentElement.offsetHeight
        );
        if (h > 0) setHeight(Math.ceil(h));
      } catch {
        // cross-origin guard — ne devrait pas arriver avec srcDoc
      }
    };

    const onLoad = () => {
      measure();
      try {
        const doc = iframe.contentDocument;
        if (!doc?.body) return;
        ro?.disconnect();
        ro = new ResizeObserver(() => measure());
        ro.observe(doc.body);
        ro.observe(doc.documentElement);
        doc.querySelectorAll("img").forEach((img) => {
          if (!img.complete) {
            img.addEventListener("load", measure, { once: true });
          }
        });
      } catch {
        /* ignore */
      }
    };

    iframe.addEventListener("load", onLoad);
    // srcDoc peut déjà être chargé
    if (iframe.contentDocument?.readyState === "complete") {
      onLoad();
    }

    return () => {
      cancelled = true;
      iframe.removeEventListener("load", onLoad);
      ro?.disconnect();
    };
  }, [srcDoc]);

  return (
    <div
      className={cn(
        "w-full min-w-0 max-w-full overflow-x-hidden",
        className
      )}
    >
      <iframe
        ref={iframeRef}
        title="Contenu du message"
        srcDoc={srcDoc}
        sandbox="allow-same-origin allow-popups allow-popups-to-escape-sandbox"
        referrerPolicy="no-referrer"
        className="block w-full max-w-full border-0 bg-transparent"
        style={{ height, width: "100%" }}
      />
    </div>
  );
}
