"use client";

import { useCallback, useEffect, useState, type MouseEvent, type ReactNode } from "react";
import { createPortal } from "react-dom";
import {
  Download,
  FileText,
  ImageIcon,
  X,
} from "lucide-react";
import { ImageLightbox, type ImageLightboxImage } from "@/components/chat/ImageLightbox";
import { formatFileSize } from "@/lib/attachments/constants";
import { cn } from "@/lib/utils/cn";

export interface AttachmentActionTarget {
  id: string;
  filename: string;
  mimeType: string;
  sizeBytes: number;
  /** URL absolue ou relative pour récupérer le fichier. */
  url: string;
  type?: "image" | "document" | string;
}

interface AttachmentActionSheetProps {
  attachment: AttachmentActionTarget | null;
  onClose: () => void;
  onPreview?: (attachment: AttachmentActionTarget) => void;
}

function isImageAttachment(att: AttachmentActionTarget): boolean {
  if (att.type === "image") return true;
  if (att.mimeType.startsWith("image/")) return true;
  return /\.(png|jpe?g|gif|webp|bmp|svg)$/i.test(att.filename);
}

function isPdfAttachment(att: AttachmentActionTarget): boolean {
  if (att.mimeType === "application/pdf") return true;
  return /\.pdf$/i.test(att.filename);
}

async function downloadAttachment(att: AttachmentActionTarget): Promise<void> {
  const url = new URL(att.url, window.location.origin);
  url.searchParams.set("download", "1");

  const response = await fetch(url.toString());
  if (!response.ok) {
    throw new Error("Téléchargement impossible");
  }

  const blob = await response.blob();
  const filename = att.filename || "telechargement";
  const mime = att.mimeType || blob.type || "application/octet-stream";

  // iOS WKWebView : <a download> est peu fiable → Web Share si possible
  try {
    const file = new File([blob], filename, { type: mime });
    if (
      typeof navigator.share === "function" &&
      typeof navigator.canShare === "function" &&
      navigator.canShare({ files: [file] })
    ) {
      await navigator.share({ files: [file], title: filename });
      return;
    }
  } catch {
    // fallback ci-dessous
  }

  const objectUrl = URL.createObjectURL(blob);
  try {
    const anchor = document.createElement("a");
    anchor.href = objectUrl;
    anchor.download = filename;
    anchor.rel = "noopener";
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 2_000);
  }
}

export { downloadAttachment, isImageAttachment, isPdfAttachment };

export function AttachmentActionSheet({
  attachment,
  onClose,
  onPreview,
}: AttachmentActionSheetProps) {
  const [busy, setBusy] = useState(false);
  const [feedback, setFeedback] = useState<string | null>(null);

  const handleKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    },
    [onClose]
  );

  useEffect(() => {
    if (!attachment) return;
    document.addEventListener("keydown", handleKeyDown);
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = previous;
    };
  }, [attachment, handleKeyDown]);

  useEffect(() => {
    setFeedback(null);
    setBusy(false);
  }, [attachment?.id]);

  if (!attachment || typeof document === "undefined") return null;

  const image = isImageAttachment(attachment);
  const pdf = isPdfAttachment(attachment);
  const canPreview = image || pdf;

  const runDownload = async () => {
    setBusy(true);
    setFeedback(null);
    try {
      await downloadAttachment(attachment);
      setFeedback("Téléchargement lancé");
    } catch {
      setFeedback("Échec du téléchargement");
    } finally {
      setBusy(false);
    }
  };

  return createPortal(
    <div className="fixed inset-0 z-[110] flex items-end justify-center sm:items-center sm:p-4">
      <button
        type="button"
        className="absolute inset-0 bg-black/40 backdrop-blur-[2px] transition-opacity duration-[var(--duration-normal)]"
        aria-label="Fermer"
        onClick={onClose}
      />

      <div
        role="dialog"
        aria-modal="true"
        aria-label={`Actions pour ${attachment.filename}`}
        className={cn(
          "glass-thick relative z-[1] w-full max-w-md overflow-hidden",
          "rounded-t-[var(--radius-2xl)] sm:rounded-[var(--radius-2xl)]",
          "animate-[sheet-up_var(--duration-normal)_var(--ease-out)]",
          "pb-[max(0.75rem,env(safe-area-inset-bottom))]"
        )}
        onClick={(event) => event.stopPropagation()}
      >
        <div className="flex justify-center pt-2.5 sm:hidden">
          <span className="h-1 w-10 rounded-full bg-border-strong" />
        </div>

        <div className="flex items-start gap-3 px-4 pb-3 pt-3">
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-[var(--radius-md)] bg-surface-hover text-accent">
            {image ? (
              <ImageIcon className="h-5 w-5" />
            ) : (
              <FileText className="h-5 w-5" />
            )}
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-medium text-foreground">
              {attachment.filename}
            </p>
            <p className="mt-0.5 text-xs text-muted">
              {image ? "Image" : pdf ? "PDF" : "Document"} ·{" "}
              {formatFileSize(attachment.sizeBytes)}
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-[var(--radius-md)] p-1.5 text-muted transition-colors hover:bg-surface-hover hover:text-foreground"
            aria-label="Fermer"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="mx-4 border-t border-border-subtle" />

        <div className="flex flex-col gap-1 p-2">
          {canPreview && onPreview && (
            <ActionRow
              icon={
                image ? (
                  <ImageIcon className="h-4 w-4" />
                ) : (
                  <FileText className="h-4 w-4" />
                )
              }
              label="Aperçu"
              onClick={() => {
                onPreview(attachment);
                onClose();
              }}
            />
          )}
          <ActionRow
            icon={<Download className="h-4 w-4" />}
            label="Télécharger"
            loading={busy}
            disabled={busy}
            onClick={() => void runDownload()}
          />
        </div>

        {feedback && (
          <p className="px-4 pb-2 text-center text-xs text-muted">
            {feedback}
          </p>
        )}

        <div className="px-2 pb-2">
          <button
            type="button"
            onClick={onClose}
            className="flex h-11 w-full items-center justify-center rounded-[var(--radius-md)] text-sm font-medium text-muted transition-colors hover:bg-surface-hover hover:text-foreground"
          >
            Annuler
          </button>
        </div>
      </div>
    </div>,
    document.body
  );
}

function ActionRow({
  icon,
  label,
  onClick,
  disabled,
  loading,
}: {
  icon: ReactNode;
  label: string;
  onClick: () => void;
  disabled?: boolean;
  loading?: boolean;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className={cn(
        "flex h-12 w-full items-center gap-3 rounded-[var(--radius-md)] px-3 text-left text-sm font-medium text-foreground",
        "transition-colors hover:bg-surface-hover active:bg-surface-active",
        "disabled:cursor-not-allowed disabled:opacity-50"
      )}
    >
      <span className="flex h-9 w-9 items-center justify-center rounded-[var(--radius-md)] bg-surface-hover text-accent">
        {icon}
      </span>
      <span className="flex-1">{loading ? `${label}…` : label}</span>
    </button>
  );
}

/** Modal plein écran pour PDF (iframe), sans navigation. */
export function DocumentPreviewModal({
  attachment,
  onClose,
}: {
  attachment: AttachmentActionTarget | null;
  onClose: () => void;
}) {
  const handleKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    },
    [onClose]
  );

  useEffect(() => {
    if (!attachment) return;
    document.addEventListener("keydown", handleKeyDown);
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = previous;
    };
  }, [attachment, handleKeyDown]);

  if (!attachment || typeof document === "undefined") return null;

  return createPortal(
    <div
      className="fixed inset-0 z-[100] flex flex-col bg-black/90 p-3 backdrop-blur-sm sm:p-5"
      role="dialog"
      aria-modal="true"
      aria-label={`Aperçu : ${attachment.filename}`}
      onClick={onClose}
    >
      <div
        className="mx-auto flex h-full w-full max-w-5xl flex-col"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="mb-2 flex items-center justify-between gap-3">
          <p
            className="min-w-0 truncate text-sm font-medium text-white"
            title={attachment.filename}
          >
            {attachment.filename}
          </p>
          <div className="flex shrink-0 items-center gap-1">
            <button
              type="button"
              onClick={() => void downloadAttachment(attachment)}
              className="inline-flex h-9 w-9 items-center justify-center rounded-[var(--radius-md)] border border-white/20 bg-white/10 text-white hover:bg-white/20"
              aria-label="Télécharger"
              title="Télécharger"
            >
              <Download className="h-4 w-4" />
            </button>
            <button
              type="button"
              onClick={onClose}
              className="inline-flex h-9 w-9 items-center justify-center rounded-[var(--radius-md)] border border-white/20 bg-white/10 text-white hover:bg-white/20"
              aria-label="Fermer"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>
        <iframe
          src={attachment.url}
          title={attachment.filename}
          className="min-h-0 w-full flex-1 rounded-[var(--radius-lg)] border border-white/15 bg-white"
        />
      </div>
    </div>,
    document.body
  );
}

/**
 * Carte type Gmail : vignette image/PDF cliquable + téléchargement.
 * Image → lightbox · PDF → modal iframe · autre → feuille d’actions.
 */
export function AttachmentFileButton({
  attachment,
  className,
  onOpen,
  onPreviewImage,
  onPreviewDocument,
}: {
  attachment: AttachmentActionTarget;
  className?: string;
  onOpen: (attachment: AttachmentActionTarget) => void;
  onPreviewImage?: (attachment: AttachmentActionTarget) => void;
  onPreviewDocument?: (attachment: AttachmentActionTarget) => void;
}) {
  const image = isImageAttachment(attachment);
  const pdf = isPdfAttachment(attachment);
  const [downloading, setDownloading] = useState(false);
  const [thumbError, setThumbError] = useState(false);

  const handleDownload = async (event: MouseEvent<HTMLButtonElement>) => {
    event.preventDefault();
    event.stopPropagation();
    if (downloading) return;
    setDownloading(true);
    try {
      await downloadAttachment(attachment);
    } catch {
      /* retry via menu */
    } finally {
      setDownloading(false);
    }
  };

  const openPreview = () => {
    if (image && onPreviewImage) {
      onPreviewImage(attachment);
      return;
    }
    if (pdf && onPreviewDocument) {
      onPreviewDocument(attachment);
      return;
    }
    onOpen(attachment);
  };

  if (image || pdf) {
    return (
      <div
        className={cn(
          "group relative w-[148px] overflow-hidden rounded-[var(--radius-lg)] border border-border bg-surface-elevated",
          "shadow-[var(--shadow-sm)] transition-[border-color,box-shadow] hover:border-border-strong hover:shadow-[var(--shadow-md)]",
          className
        )}
      >
        <button
          type="button"
          onClick={openPreview}
          className="block w-full text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-accent"
          aria-label={`Aperçu de ${attachment.filename}`}
        >
          <div className="relative flex h-[104px] items-center justify-center overflow-hidden bg-surface-hover">
            {image && !thumbError ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={attachment.url}
                alt=""
                className="h-full w-full object-cover"
                onError={() => setThumbError(true)}
              />
            ) : pdf && !thumbError ? (
              <>
                <iframe
                  src={`${attachment.url}#page=1&view=FitH&toolbar=0&navpanes=0`}
                  title=""
                  tabIndex={-1}
                  aria-hidden
                  className="pointer-events-none absolute inset-[-8%] h-[116%] w-[116%] origin-top scale-[0.92] border-0 bg-white"
                  onError={() => setThumbError(true)}
                />
                <span className="absolute bottom-1.5 left-1.5 rounded-[var(--radius-sm)] bg-error/90 px-1.5 py-0.5 text-[10px] font-bold uppercase tracking-wide text-foreground">
                  PDF
                </span>
              </>
            ) : (
              <div className="flex flex-col items-center gap-1 text-muted">
                {image ? (
                  <ImageIcon className="h-7 w-7" strokeWidth={1.5} />
                ) : (
                  <FileText className="h-7 w-7" strokeWidth={1.5} />
                )}
                {pdf && (
                  <span className="text-[10px] font-semibold uppercase text-error">
                    PDF
                  </span>
                )}
              </div>
            )}
          </div>
          <div className="border-t border-border-subtle px-2.5 py-2">
            <p
              className="truncate text-[12px] font-medium text-foreground"
              title={attachment.filename}
            >
              {attachment.filename}
            </p>
            <p className="mt-0.5 text-[11px] text-muted">
              {formatFileSize(attachment.sizeBytes)}
            </p>
          </div>
        </button>
        <button
          type="button"
          onClick={(e) => void handleDownload(e)}
          disabled={downloading}
          className={cn(
            "absolute right-1.5 top-1.5 flex h-8 w-8 items-center justify-center rounded-[var(--radius-md)]",
            "border border-border bg-background/90 text-foreground shadow-sm backdrop-blur-sm",
            "opacity-100 transition-opacity md:opacity-0 md:group-hover:opacity-100",
            "hover:bg-surface-elevated disabled:opacity-50"
          )}
          aria-label={`Télécharger ${attachment.filename}`}
          title="Télécharger"
        >
          {downloading ? (
            <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-muted border-t-transparent" />
          ) : (
            <Download className="h-3.5 w-3.5" />
          )}
        </button>
      </div>
    );
  }

  return (
    <div
      className={cn(
        "flex min-h-[44px] w-full items-center gap-1 rounded-[var(--radius-md)] border border-border bg-surface-elevated pl-3 pr-1.5 py-1.5",
        "hover:border-border-strong hover:bg-surface-hover",
        className
      )}
    >
      <button
        type="button"
        onClick={() => onOpen(attachment)}
        className={cn(
          "flex min-w-0 flex-1 items-center gap-2 py-1 text-left transition-colors",
          "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40"
        )}
        aria-label={`Options pour ${attachment.filename}`}
      >
        <FileText className="h-4 w-4 shrink-0 text-accent" />
        <span className="min-w-0 flex-1 truncate text-sm font-medium text-foreground">
          {attachment.filename}
        </span>
        <span className="shrink-0 text-xs text-muted">
          {formatFileSize(attachment.sizeBytes)}
        </span>
      </button>
      <button
        type="button"
        onClick={(e) => void handleDownload(e)}
        disabled={downloading}
        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[var(--radius-md)] text-muted transition-colors hover:bg-surface-active hover:text-foreground disabled:opacity-50"
        aria-label={`Télécharger ${attachment.filename}`}
        title="Télécharger"
      >
        {downloading ? (
          <span className="h-4 w-4 animate-spin rounded-full border-2 border-muted border-t-transparent" />
        ) : (
          <Download className="h-4 w-4" />
        )}
      </button>
    </div>
  );
}

/** Liste de PJ mail avec lightbox image + modal PDF. */
export function AttachmentGallery({
  attachments,
  className,
}: {
  attachments: AttachmentActionTarget[];
  className?: string;
}) {
  const [sheet, setSheet] = useState<AttachmentActionTarget | null>(null);
  const [lightbox, setLightbox] = useState<ImageLightboxImage | null>(null);
  const [documentPreview, setDocumentPreview] =
    useState<AttachmentActionTarget | null>(null);

  if (attachments.length === 0) return null;

  return (
    <>
      <div className={cn("mt-3 flex flex-wrap gap-2.5", className)}>
        {attachments.map((att) => (
          <AttachmentFileButton
            key={att.id}
            attachment={att}
            onOpen={setSheet}
            onPreviewImage={(a) =>
              setLightbox({ src: a.url, alt: a.filename, filename: a.filename })
            }
            onPreviewDocument={setDocumentPreview}
          />
        ))}
      </div>
      <AttachmentActionSheet
        attachment={sheet}
        onClose={() => setSheet(null)}
        onPreview={(a) => {
          if (isImageAttachment(a)) {
            setLightbox({ src: a.url, alt: a.filename, filename: a.filename });
          } else if (isPdfAttachment(a)) {
            setDocumentPreview(a);
          }
        }}
      />
      <ImageLightbox image={lightbox} onClose={() => setLightbox(null)} />
      <DocumentPreviewModal
        attachment={documentPreview}
        onClose={() => setDocumentPreview(null)}
      />
    </>
  );
}
