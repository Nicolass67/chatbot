import { Suspense } from "react";
import FilesWorkspace from "./FilesWorkspace";

export default function FilesRoutePage() {
  return (
    <Suspense
      fallback={
        <div className="flex h-full items-center justify-center text-sm text-muted">
          Chargement Files…
        </div>
      }
    >
      <FilesWorkspace />
    </Suspense>
  );
}
