"use client";

import { Suspense, useEffect } from "react";
import { useParams, useRouter, useSearchParams } from "next/navigation";

function MailThreadRedirectInner() {
  const params = useParams<{ id: string }>();
  const searchParams = useSearchParams();
  const router = useRouter();

  useEffect(() => {
    const message = searchParams.get("message");
    const qs = new URLSearchParams({ thread: params.id });
    if (message) qs.set("message", message);
    router.replace(`/mail?${qs.toString()}`);
  }, [params.id, searchParams, router]);

  return (
    <div className="flex h-[100dvh] items-center justify-center text-sm text-muted-foreground">
      Redirection…
    </div>
  );
}

export default function MailThreadRedirectPage() {
  return (
    <Suspense
      fallback={
        <div className="flex h-[100dvh] items-center justify-center text-sm text-muted-foreground">
          Chargement…
        </div>
      }
    >
      <MailThreadRedirectInner />
    </Suspense>
  );
}
