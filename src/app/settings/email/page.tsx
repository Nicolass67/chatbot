"use client";

import Link from "next/link";
import { Suspense } from "react";
import {
  SettingsLayout,
  SettingsSection,
} from "@/components/ui/SettingsLayout";
import { Button } from "@/components/ui/Button";
import { Spinner } from "@/components/ui/Spinner";
import { EmailOAuthPanel } from "@/components/settings/EmailOAuthPanel";

function EmailOAuthPanelFallback() {
  return (
    <div className="flex items-center justify-center gap-2 py-8 text-muted">
      <Spinner />
      <span className="text-sm">Chargement…</span>
    </div>
  );
}

export default function EmailSettingsPage() {
  return (
    <SettingsLayout title="Email" backHref="/settings">
      <div className="space-y-8">
        <SettingsSection
          title="Gmail"
          description="Connexion OAuth pour lire, rechercher et envoyer des emails depuis l'assistant."
        >
          <Suspense fallback={<EmailOAuthPanelFallback />}>
            <EmailOAuthPanel />
          </Suspense>
        </SettingsSection>

        <SettingsSection
          title="Envoi sécurisé"
          description="L'assistant ne peut jamais envoyer un email sans votre confirmation explicite dans l'interface."
        >
          <ul className="list-inside list-disc space-y-1 text-sm text-muted-foreground">
            <li>Les brouillons doivent être validés avant envoi</li>
            <li>Chaque envoi demande une confirmation avec récapitulatif</li>
            <li>Les tokens OAuth restent chiffrés côté serveur</li>
          </ul>
        </SettingsSection>

        <Link href="/settings">
          <Button variant="secondary" size="sm">
            Retour aux paramètres
          </Button>
        </Link>
      </div>
    </SettingsLayout>
  );
}
