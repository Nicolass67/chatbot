"use client";

import { useCallback, useEffect } from "react";
import { createPortal } from "react-dom";
import { Download, X } from "lucide-react";
import { IconButton } from "@/components/ui/IconButton";
import { cn } from "@/lib/utils/cn";

export interface ImageLightboxImage {
  src: string;
  alt: string;
  filename?: string;
}

interface ImageLightboxProps {
  image: ImageLightboxImage | null;
  onClose: () => void;
}

const toolbarButtonClass =
  "border-white/20 bg-white/10 text-white hover:bg-white/20 hover:text-white";

export function ImageLightbox({ image, onClose }: ImageLightboxProps) {
  const handleKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    },
    [onClose]
  );

  useEffect(() => {
    if (!image) return;

    document.addEventListener("keydown", handleKeyDown);
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";

    return () => {
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = previousOverflow;
    };
  }, [image, handleKeyDown]);

  if (!image || typeof document === "undefined") return null;

  const filename = image.filename ?? image.alt;

  return createPortal(
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/85 p-4 backdrop-blur-sm"
      role="dialog"
      aria-modal="true"
      aria-label={`Aperçu : ${filename}`}
      onClick={onClose}
    >
      <figure
        className="flex max-h-[min(92dvh,calc(100dvh-2rem))] max-w-[min(96vw,1200px)] flex-col"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="mb-2 flex items-center justify-between gap-3 px-0.5">
          <figcaption
            className="min-w-0 truncate text-sm font-medium text-white/90"
            title={filename}
          >
            {filename}
          </figcaption>
          <div className="flex shrink-0 items-center gap-1">
            <a
              href={image.src}
              download={filename}
              className={cn(
                "inline-flex h-9 w-9 items-center justify-center rounded-[var(--radius-md)] transition-[background-color,color,transform] duration-[var(--duration-fast)] focus-visible:outline-none active:scale-[0.96]",
                toolbarButtonClass
              )}
              aria-label="Télécharger l'image"
              title="Télécharger"
            >
              <Download className="h-4 w-4" />
            </a>
            <IconButton
              variant="subtle"
              size="md"
              label="Fermer"
              onClick={onClose}
              className={toolbarButtonClass}
            >
              <X className="h-4 w-4" />
            </IconButton>
          </div>
        </div>

        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={image.src}
          alt={image.alt}
          className="max-h-[min(80dvh,calc(100dvh-6rem))] w-full rounded-lg object-contain shadow-2xl"
        />
      </figure>
    </div>,
    document.body
  );
}
