"use client";

import { useEffect, useState } from "react";
import dynamic from "next/dynamic";
import { ChevronLeft, ChevronRight, X } from "lucide-react";
import { IconButton } from "@/components/ui/IconButton";
import { Spinner } from "@/components/ui/Spinner";
import { Button } from "@/components/ui/Button";
import { openExternal } from "@/lib/native/open-external";
import { cn } from "@/lib/utils/cn";
import { formatBytes } from "./types";

const MarkdownRenderer = dynamic(
  () =>
    import("@/components/markdown/MarkdownRenderer").then(
      (m) => m.MarkdownRenderer
    ),
  {
    ssr: false,
    loading: () => (
      <div className="flex items-center gap-2 text-sm text-zinc-500">
        <Spinner className="h-4 w-4" />
        Rendu…
      </div>
    ),
  }
);

type PreviewPayload =
  | {
      kind: "markdown" | "json" | "csv" | "text" | "extract";
      text: string;
      truncated?: boolean;
      notice?: string;
      name: string;
      sizeBytes: number;
      language?: string;
    }
  | {
      kind: "image" | "pdf";
      url: string;
      name: string;
      sizeBytes: number;
    }
  | {
      kind: "unsupported";
      name: string;
      message: string;
      sizeBytes: number;
    };

interface FilesPreviewPaneProps {
  fileId: string | null;
  fileName?: string;
  onClose: () => void;
  onPrev?: () => void;
  onNext?: () => void;
  className?: string;
}

function renderCsv(text: string) {
  const lines = text.split(/\r?\n/).filter((l) => l.length > 0).slice(0, 40);
  const rows = lines.map((line) => line.split(",").slice(0, 12));
  return (
    <div className="overflow-auto">
      <table className="min-w-full border-collapse text-left text-xs">
        <tbody>
          {rows.map((row, i) => (
            <tr key={i} className="border-b border-border-subtle">
              {row.map((cell, j) => (
                <td key={j} className="whitespace-pre-wrap px-2 py-1 align-top">
                  {cell}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function revokeIfBlobUrl(url: string) {
  if (url.startsWith("blob:")) URL.revokeObjectURL(url);
}

export function FilesPreviewPane({
  fileId,
  fileName,
  onClose,
  onPrev,
  onNext,
  className,
}: FilesPreviewPaneProps) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [payload, setPayload] = useState<PreviewPayload | null>(null);

  useEffect(() => {
    if (!fileId) {
      setPayload(null);
      return;
    }
    let cancelled = false;
    const timer = window.setTimeout(() => {
      void (async () => {
        setLoading(true);
        setError(null);
        try {
          const res = await fetch(
            `/api/files/content?fileId=${encodeURIComponent(fileId)}`
          );
          const contentType = res.headers.get("content-type") ?? "";
          if (!res.ok) {
            const data = (await res.json()) as { error?: string };
            throw new Error(data.error ?? "Aperçu impossible");
          }
          if (
            contentType.startsWith("image/") ||
            contentType.includes("application/pdf")
          ) {
            const blob = await res.blob();
            const url = URL.createObjectURL(blob);
            if (cancelled) {
              revokeIfBlobUrl(url);
              return;
            }
            setPayload({
              kind: contentType.includes("application/pdf") ? "pdf" : "image",
              url,
              name: fileName ?? (contentType.includes("pdf") ? "document.pdf" : "image"),
              sizeBytes: blob.size,
            });
          } else {
            const data = (await res.json()) as PreviewPayload & {
              error?: string;
            };
            if (cancelled) return;
            setPayload(data);
          }
        } catch (err) {
          if (!cancelled) {
            setError(err instanceof Error ? err.message : "Erreur");
            setPayload(null);
          }
        } finally {
          if (!cancelled) setLoading(false);
        }
      })();
    }, 80);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
      setPayload((prev) => {
        if (prev && (prev.kind === "image" || prev.kind === "pdf") && "url" in prev) {
          revokeIfBlobUrl(prev.url);
        }
        return null;
      });
    };
  }, [fileId, fileName]);

  return (
    <div className={cn("flex h-full min-h-0 flex-col", className)}>
      <div className="flex items-center gap-1 border-b border-border-subtle px-2 py-1.5">
        <IconButton label="Précédent" size="sm" disabled={!onPrev} onClick={onPrev}>
          <ChevronLeft className="h-4 w-4" />
        </IconButton>
        <IconButton label="Suivant" size="sm" disabled={!onNext} onClick={onNext}>
          <ChevronRight className="h-4 w-4" />
        </IconButton>
        <div className="min-w-0 flex-1 px-1">
          <p className="truncate text-sm font-medium">
            {payload && "name" in payload ? payload.name : fileName ?? "Aperçu"}
          </p>
        </div>
        <IconButton
          label="Fermer l'aperçu"
          size="sm"
          onClick={(e) => {
            e.preventDefault();
            e.stopPropagation();
            onClose();
          }}
        >
          <X className="h-4 w-4" />
        </IconButton>
      </div>

      <div
        className={cn(
          "min-h-0 flex-1",
          payload?.kind === "pdf" ? "overflow-hidden p-0" : "overflow-auto p-3"
        )}
      >
        {loading && (
          <div className="flex items-center justify-center gap-2 py-16 text-sm text-muted">
            <Spinner size="sm" />
            Chargement de l’aperçu…
          </div>
        )}
        {error && !loading && (
          <div className="m-3 rounded-[var(--radius-md)] border border-error/30 bg-error/10 px-3 py-3 text-sm text-error">
            {error}
          </div>
        )}
        {!loading && !error && payload?.kind === "image" && (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={payload.url}
            alt={payload.name}
            className="mx-auto max-h-full max-w-full object-contain p-3"
          />
        )}
        {!loading && !error && payload?.kind === "pdf" && (
          <div className="flex h-full min-h-0 flex-col">
            <iframe
              title={payload.name}
              src={`${payload.url}#toolbar=1&navpanes=0`}
              className="h-full min-h-[40vh] w-full flex-1 border-0 bg-surface"
            />
            <div className="flex shrink-0 justify-center border-t border-border-subtle p-2">
              <Button
                type="button"
                variant="secondary"
                size="sm"
                onClick={() => {
                  const openUrl = `/api/files/content?fileId=${encodeURIComponent(fileId!)}`;
                  void openExternal(openUrl);
                }}
              >
                Ouvrir le PDF
              </Button>
            </div>
          </div>
        )}
        {!loading && !error && payload?.kind === "markdown" && (
          <MarkdownRenderer content={payload.text} />
        )}
        {!loading && !error && payload?.kind === "json" && (
          <pre className="overflow-auto rounded-[var(--radius-md)] bg-surface-elevated p-3 text-xs">
            <code className="language-json hljs">
              {(() => {
                try {
                  return JSON.stringify(JSON.parse(payload.text), null, 2);
                } catch {
                  return payload.text;
                }
              })()}
            </code>
          </pre>
        )}
        {!loading && !error && payload?.kind === "csv" && renderCsv(payload.text)}
        {!loading &&
          !error &&
          (payload?.kind === "text" || payload?.kind === "extract") && (
            <div className="space-y-2">
              {"notice" in payload && payload.notice && (
                <p className="text-xs text-muted">{payload.notice}</p>
              )}
              <pre className="overflow-auto whitespace-pre-wrap break-words rounded-[var(--radius-md)] bg-surface-elevated p-3 font-mono text-xs leading-relaxed">
                {payload.text}
              </pre>
            </div>
          )}
        {!loading && !error && payload?.kind === "unsupported" && (
          <div className="py-10 text-center text-sm text-muted">
            <p className="font-medium text-foreground">{payload.name}</p>
            <p className="mt-2">{payload.message}</p>
            <p className="mt-1 text-xs">{formatBytes(payload.sizeBytes)}</p>
          </div>
        )}
        {!loading &&
          !error &&
          payload &&
          "truncated" in payload &&
          payload.truncated && (
            <p className="mt-3 text-xs text-muted">… contenu tronqué</p>
          )}
      </div>
    </div>
  );
}
