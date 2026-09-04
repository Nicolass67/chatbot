"use client";

import { Suspense } from "react";
import MailWorkspace from "./MailWorkspace";

export default function MailInboxPage() {
  return (
    <Suspense
      fallback={
        <div className="flex h-[100dvh] items-center justify-center text-sm text-muted-foreground">
          Chargement…
        </div>
      }
    >
      <MailWorkspace />
    </Suspense>
  );
}
