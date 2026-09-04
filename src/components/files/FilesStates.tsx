"use client";

import { Button } from "@/components/ui/Button";
import { Spinner } from "@/components/ui/Spinner";

export function FilesLoadingState() {
  return (
    <div className="flex flex-1 flex-col divide-y divide-border-subtle">
      {Array.from({ length: 10 }).map((_, i) => (
        <div
          key={i}
          className="flex h-10 items-center gap-3 px-3 animate-pulse"
          style={{ opacity: 1 - i * 0.07 }}
        >
          <div className="h-3.5 w-3.5 shrink-0 rounded-sm bg-border-subtle" />
          <div className="h-2.5 flex-1 rounded-sm bg-border-subtle" />
          <div className="hidden h-2.5 w-16 rounded-sm bg-border-subtle/70 sm:block" />
          <div className="hidden h-2.5 w-20 rounded-sm bg-border-subtle/70 md:block" />
        </div>
      ))}
    </div>
  );
}

export function FilesEmptyFolder() {
  return (
    <div className="flex flex-1 flex-col justify-center px-6 py-16">
      <h2 className="text-[15px] font-medium tracking-[-0.01em]">Ce dossier est vide</h2>
      <p className="mt-1.5 max-w-sm text-[13px] text-muted">
        Les fichiers ajoutés ici apparaîtront automatiquement.
      </p>
    </div>
  );
}

export function FilesEmptySearch({ onClear }: { onClear: () => void }) {
  return (
    <div className="flex flex-1 flex-col justify-center gap-3 px-6 py-16">
      <div>
        <h2 className="text-[15px] font-medium tracking-[-0.01em]">Aucun résultat</h2>
        <p className="mt-1.5 max-w-md text-[13px] text-muted">
          Aucun fichier trouvé par nom ni dans le contenu indexé.
        </p>
      </div>
      <Button type="button" size="sm" variant="secondary" onClick={onClear} className="w-fit">
        Effacer la recherche
      </Button>
    </div>
  );
}

export function FilesErrorState({
  message,
  onRetry,
}: {
  message: string;
  onRetry?: () => void;
}) {
  return (
    <div className="flex flex-1 flex-col justify-center gap-3 px-6 py-16">
      <div>
        <h2 className="text-[15px] font-medium tracking-[-0.01em]">Impossible de charger</h2>
        <p className="mt-1.5 max-w-md text-[13px] text-muted">{message}</p>
      </div>
      {onRetry && (
        <Button type="button" size="sm" onClick={onRetry} className="w-fit">
          Réessayer
        </Button>
      )}
    </div>
  );
}

export function FilesDisabledState() {
  return (
    <div className="flex h-[100dvh] flex-col justify-center gap-3 p-8">
      <h1 className="text-[15px] font-medium tracking-[-0.01em]">Files désactivé</h1>
      <p className="max-w-md text-[13px] text-muted">
        Activez FILES_ENABLED puis configurez les roots (Documents / Downloads).
      </p>
      <a href="/settings/files" className="w-fit text-[13px] text-foreground underline decoration-muted underline-offset-2">
        Paramètres Files
      </a>
    </div>
  );
}

export function FilesBusyInline() {
  return (
    <div className="flex items-center justify-center gap-2 py-10 text-sm text-muted">
      <Spinner size="sm" />
      Chargement…
    </div>
  );
}
