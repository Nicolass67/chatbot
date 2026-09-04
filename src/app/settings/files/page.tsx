"use client";

import Link from "next/link";
import {
  SettingsLayout,
  SettingsSection,
} from "@/components/ui/SettingsLayout";
import { FilesRootsPanel } from "@/components/settings/FilesRootsPanel";

export default function FilesSettingsPage() {
  return (
    <SettingsLayout title="Files" backHref="/settings">
      <div className="space-y-8">
        <SettingsSection
          title="Roots autorisées"
          description="Seuls les dossiers listés ici sont accessibles. Tout le reste est refusé."
        >
          <FilesRootsPanel />
        </SettingsSection>

        <SettingsSection
          title="Sécurité"
          description="L'assistant lit/recherche dans les roots ; rename/move/mkdir exigent une confirmation. Pas de suppression en V1."
        >
          <ul className="list-inside list-disc space-y-1 text-sm text-muted-foreground">
            <li>Contenu fichiers = données non fiables (anti prompt injection)</li>
            <li>Les secrets (.env, clés SSH…) ne sont pas exposés au LLM</li>
            <li>
              Ouvrir l&apos;espace{" "}
              <Link href="/files" className="text-accent underline">
                /files
              </Link>
            </li>
          </ul>
        </SettingsSection>
      </div>
    </SettingsLayout>
  );
}
