"use client";

import { useCallback, useEffect, useRef, useState, type MouseEvent } from "react";
import { Download, FileText, ImageIcon, Loader2, X } from "lucide-react";
import { ImageLightbox, type ImageLightboxImage } from "@/components/chat/ImageLightbox";
import {
  AttachmentActionSheet,
  downloadAttachment,
  type AttachmentActionTarget,
} from "@/components/attachments/AttachmentActionSheet";
import { formatFileSize } from "@/lib/attachments/constants";
import { cn } from "@/lib/utils/cn";

export interface PendingAttachment {
  id: string;
  filename: string;
  mimeType: string;
  sizeBytes: number;
  type: "image" | "document";
  previewUrl?: string;
  uploading?: boolean;
  error?: string;
}

function AttachmentPreviewCard({
  item,
  onRemove,
  onOpen,
}: {
  item: PendingAttachment;
  onRemove: (id: string) => void;
  onOpen: (item: PendingAttachment) => void;
}) {
  return (
    <div className="flex w-[104px] shrink-0 snap-start flex-col rounded-xl border border-border bg-surface p-2 sm:w-[120px] md:w-[132px]">
      <div className="relative mb-1 flex h-14 items-center justify-center overflow-hidden rounded-lg bg-surface-hover sm:h-16">
        <button
          type="button"
          onClick={(event) => {
            event.stopPropagation();
            onRemove(item.id);
          }}
          className="absolute right-1 top-1 z-10 flex h-6 w-6 items-center justify-center rounded-full border border-border bg-background/95 text-muted shadow-sm backdrop-blur-sm hover:text-foreground"
          aria-label={`Supprimer ${item.filename}`}
        >
          <X className="h-3.5 w-3.5" />
        </button>

        <button
          type="button"
          className="flex h-full w-full items-center justify-center"
          onClick={() => {
            if (item.uploading || item.error) return;
            onOpen(item);
          }}
          disabled={Boolean(item.uploading || item.error)}
          aria-label={`Options pour ${item.filename}`}
        >
          {item.uploading ? (
            <Loader2 className="h-5 w-5 animate-spin text-muted" />
          ) : item.type === "image" && item.previewUrl ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={item.previewUrl}
              alt={item.filename}
              className="h-full w-full object-cover"
            />
          ) : item.type === "image" ? (
            <ImageIcon className="h-6 w-6 text-muted" />
          ) : (
            <FileText className="h-6 w-6 text-muted" />
          )}
        </button>
      </div>

      <p className="truncate text-[11px] font-medium" title={item.filename}>
        {item.filename}
      </p>
      <p className="truncate text-[10px] text-muted">
        {item.type === "image" ? "Image" : "Document"} ·{" "}
        {formatFileSize(item.sizeBytes)}
      </p>
      {item.error && (
        <p className="mt-0.5 truncate text-[10px] text-red-500" title={item.error}>
          {item.error}
        </p>
      )}
    </div>
  );
}

interface AttachmentPreviewListProps {
  items: PendingAttachment[];
  onRemove: (id: string) => void;
  className?: string;
}

export function AttachmentPreviewList({
  items,
  onRemove,
  className,
}: AttachmentPreviewListProps) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const [hasOverflow, setHasOverflow] = useState(false);
  const [scrollRatio, setScrollRatio] = useState(0);
  const [active, setActive] = useState<AttachmentActionTarget | null>(null);
  const [lightboxImage, setLightboxImage] = useState<ImageLightboxImage | null>(
    null
  );

  const updateScrollState = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    const overflow = el.scrollWidth > el.clientWidth + 2;
    setHasOverflow(overflow);
    const maxScroll = el.scrollWidth - el.clientWidth;
    setScrollRatio(maxScroll > 0 ? el.scrollLeft / maxScroll : 0);
  }, []);

  useEffect(() => {
    updateScrollState();
    const el = scrollRef.current;
    if (!el) return;

    const observer = new ResizeObserver(updateScrollState);
    observer.observe(el);
    el.addEventListener("scroll", updateScrollState, { passive: true });
    return () => {
      observer.disconnect();
      el.removeEventListener("scroll", updateScrollState);
    };
  }, [items, updateScrollState]);

  if (items.length === 0) return null;

  return (
    <div className={cn("w-full", className)}>
      <div
        ref={scrollRef}
        className={cn(
          "flex gap-2 overflow-x-auto scroll-smooth pb-1",
          "snap-x snap-mandatory touch-pan-x",
          "[-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        )}
      >
        {items.map((item) => (
          <AttachmentPreviewCard
            key={item.id}
            item={item}
            onRemove={onRemove}
            onOpen={(att) =>
              setActive({
                id: att.id,
                filename: att.filename,
                mimeType: att.mimeType,
                sizeBytes: att.sizeBytes,
                type: att.type,
                url: att.previewUrl || `/api/attachments/${att.id}`,
              })
            }
          />
        ))}
      </div>
      {hasOverflow && (
        <input
          type="range"
          min={0}
          max={100}
          value={Math.round(scrollRatio * 100)}
          onChange={(e) => {
            const el = scrollRef.current;
            if (!el) return;
            const maxScroll = el.scrollWidth - el.clientWidth;
            el.scrollLeft = (Number(e.target.value) / 100) * maxScroll;
          }}
          className="attachment-scroll-slider mt-1.5 w-full"
          aria-label="Défiler les pièces jointes"
        />
      )}
      <AttachmentActionSheet
        attachment={active}
        onClose={() => setActive(null)}
        onPreview={(att) =>
          setLightboxImage({
            src: att.url,
            alt: att.filename,
            filename: att.filename,
          })
        }
      />
      <ImageLightbox
        image={lightboxImage}
        onClose={() => setLightboxImage(null)}
      />
    </div>
  );
}

interface MessageAttachmentsProps {
  attachments: Array<{
    id: string;
    filename: string;
    mimeType: string;
    sizeBytes: number;
    type: string;
  }>;
}

export function MessageAttachments({ attachments }: MessageAttachmentsProps) {
  const [lightboxImage, setLightboxImage] = useState<ImageLightboxImage | null>(
    null
  );
  const [active, setActive] = useState<AttachmentActionTarget | null>(null);
  const [downloadingId, setDownloadingId] = useState<string | null>(null);

  if (attachments.length === 0) return null;

  const useCarousel = attachments.length > 3;

  const toTarget = (
    att: MessageAttachmentsProps["attachments"][number]
  ): AttachmentActionTarget => ({
    id: att.id,
    filename: att.filename,
    mimeType: att.mimeType,
    sizeBytes: att.sizeBytes,
    type: att.type,
    url: `/api/attachments/${att.id}`,
  });

  const handleDownload = async (
    att: MessageAttachmentsProps["attachments"][number],
    event: MouseEvent
  ) => {
    event.preventDefault();
    event.stopPropagation();
    if (downloadingId) return;
    setDownloadingId(att.id);
    try {
      await downloadAttachment(toTarget(att));
    } catch {
      /* ignore */
    } finally {
      setDownloadingId(null);
    }
  };

  const content = attachments.map((att) =>
    att.type === "image" ? (
      <div
        key={att.id}
        className={cn(
          "relative shrink-0 snap-start overflow-hidden rounded-lg border border-border",
          useCarousel && "w-[min(72vw,280px)]"
        )}
      >
        <button
          type="button"
          onClick={() => setActive(toTarget(att))}
          className="block w-full text-left transition-shadow hover:ring-2 hover:ring-accent/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent"
          aria-label={`Options pour ${att.filename}`}
        >
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={`/api/attachments/${att.id}`}
            alt={att.filename}
            className={cn(
              "max-w-full object-contain",
              useCarousel ? "max-h-40 w-full" : "max-h-48"
            )}
          />
        </button>
        <button
          type="button"
          onClick={(e) => void handleDownload(att, e)}
          disabled={downloadingId === att.id}
          className="absolute bottom-2 right-2 flex h-8 w-8 items-center justify-center rounded-full border border-border bg-background/90 text-foreground shadow-sm backdrop-blur-sm hover:bg-surface disabled:opacity-50"
          aria-label={`Télécharger ${att.filename}`}
          title="Télécharger"
        >
          <Download className="h-3.5 w-3.5" />
        </button>
      </div>
    ) : (
      <div
        key={att.id}
        className={cn(
          "flex min-h-[44px] shrink-0 snap-start items-center gap-1 rounded-lg border border-border bg-surface-hover py-1.5 pl-3 pr-1.5",
          useCarousel && "max-w-[min(72vw,280px)]"
        )}
      >
        <button
          type="button"
          onClick={() => setActive(toTarget(att))}
          className="flex min-w-0 flex-1 items-center gap-2 text-left text-sm hover:opacity-90"
          aria-label={`Options pour ${att.filename}`}
        >
          <FileText className="h-4 w-4 shrink-0 text-muted" />
          <span className="truncate">{att.filename}</span>
          <span className="text-xs text-muted">
            {formatFileSize(att.sizeBytes)}
          </span>
        </button>
        <button
          type="button"
          onClick={(e) => void handleDownload(att, e)}
          disabled={downloadingId === att.id}
          className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[var(--radius-md)] text-muted transition-colors hover:bg-surface hover:text-foreground disabled:opacity-50"
          aria-label={`Télécharger ${att.filename}`}
          title="Télécharger"
        >
          {downloadingId === att.id ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Download className="h-4 w-4" />
          )}
        </button>
      </div>
    )
  );

  const list = !useCarousel ? (
    <div className="mt-2 flex flex-wrap gap-2">{content}</div>
  ) : (
    <div
      className={cn(
        "mt-2 flex gap-2 overflow-x-auto scroll-smooth pb-1",
        "snap-x snap-mandatory touch-pan-x",
        "[-ms-overflow-style:none] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
      )}
    >
      {content}
    </div>
  );

  return (
    <>
      {list}
      <AttachmentActionSheet
        attachment={active}
        onClose={() => setActive(null)}
        onPreview={(a) =>
          setLightboxImage({
            src: a.url,
            alt: a.filename,
            filename: a.filename,
          })
        }
      />
      <ImageLightbox
        image={lightboxImage}
        onClose={() => setLightboxImage(null)}
      />
    </>
  );
}
