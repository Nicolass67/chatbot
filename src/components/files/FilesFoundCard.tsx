"use client";

import Link from "next/link";
import { Download, Eye, FileText, FolderOpen } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { cn } from "@/lib/utils/cn";

export interface FilesFoundItem {
  fileId: string;
  filename: string;
  relativePath?: string;
  rootId?: string;
  sizeBytes?: number;
  mtimeMs?: number;
  extension?: string;
}

interface FilesFoundCardProps {
  files: FilesFoundItem[];
  className?: string;
}

function formatSize(bytes?: number): string | null {
  if (bytes == null || bytes <= 0) return null;
  if (bytes < 1024) return `${bytes} o`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} Ko`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} Mo`;
}

export function FilesFoundCard({ files, className }: FilesFoundCardProps) {
  if (!files.length) return null;

  return (
    <div className={cn("mb-3 space-y-2", className)}>
      {files.map((file) => {
        const size = formatSize(file.sizeBytes);
        const filesHref = file.rootId
          ? `/files?root=${encodeURIComponent(file.rootId)}&q=${encodeURIComponent(file.filename)}`
          : `/files?q=${encodeURIComponent(file.filename)}`;
        const openHref = `/api/files/content?fileId=${encodeURIComponent(file.fileId)}`;

        return (
          <div
            key={file.fileId}
            className="rounded-[var(--radius-lg)] border border-border-subtle bg-surface/50 px-3.5 py-3"
          >
            <div className="flex items-start gap-3">
              <FileText className="mt-0.5 h-4 w-4 shrink-0 text-accent" />
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium text-foreground">
                  {file.filename}
                </p>
                <p className="truncate text-xs text-muted">
                  {[file.relativePath, size].filter(Boolean).join(" · ")}
                </p>
              </div>
            </div>
            <div className="mt-2.5 flex flex-wrap gap-2">
              <a href={openHref} target="_blank" rel="noopener noreferrer">
                <Button variant="primary" size="sm" type="button">
                  <Eye className="h-3.5 w-3.5" />
                  Ouvrir
                </Button>
              </a>
              <a href={openHref} download={file.filename}>
                <Button variant="secondary" size="sm" type="button">
                  <Download className="h-3.5 w-3.5" />
                  Télécharger
                </Button>
              </a>
              <Link href={filesHref}>
                <Button variant="ghost" size="sm" type="button">
                  <FolderOpen className="h-3.5 w-3.5" />
                  Voir dans Files
                </Button>
              </Link>
            </div>
          </div>
        );
      })}
    </div>
  );
}
