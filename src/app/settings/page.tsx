"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import {
  SettingsLayout,
  SettingsSection,
  SettingsField,
  settingsInputClass,
  settingsSelectTriggerClass,
} from "@/components/ui/SettingsLayout";
import { Dropdown } from "@/components/ui/Dropdown";
import { Switch } from "@/components/ui/Switch";
import { Button } from "@/components/ui/Button";
import { Badge } from "@/components/ui/Badge";
import { Spinner } from "@/components/ui/Spinner";
import { WakeTestPanel } from "@/components/settings/WakeTestPanel";
import { ShutdownPcPanel } from "@/components/settings/ShutdownPcPanel";
import { openExternal } from "@/lib/native/open-external";

interface Settings {
  selectedModel: string;
  temperature: number;
  maxTokens: number;
  contextLength: number;
  systemPrompt: string;
  memoryEnabled: boolean;
  webSearchEnabled: boolean;
  webSearchMaxResults: number;
  webSearchTimeoutMs: number;
  idleTimeoutMinutes: number;
  defaultReasoningEffort: string | null;
}

export default function SettingsPage() {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [models, setModels] = useState<Array<{ id: string }>>([]);
  const [health, setHealth] = useState<string>("...");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    Promise.all([
      fetch("/api/settings").then((r) => r.json()),
      fetch("/api/lm-studio/models").then((r) => r.json()),
      fetch("/api/lm-studio/health").then((r) => r.json()),
    ]).then(([s, m, h]) => {
      setSettings(s as Settings);
      setModels((m as { data?: Array<{ id: string }> }).data ?? []);
      setHealth((h as { ok?: boolean }).ok ? "Connecté" : "Hors ligne");
    });
  }, []);

  const save = async (partial: Partial<Settings>) => {
    if (!settings) return;
    setSaving(true);
    const updated = { ...settings, ...partial };
    const res = await fetch("/api/settings", {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(partial),
    });
    if (res.ok) setSettings(await res.json());
    else setSettings(updated);
    setSaving(false);
  };

  if (!settings) {
    return (
      <div className="flex min-h-dvh items-center justify-center gap-2 text-muted">
        <Spinner />
        <span>Chargement…</span>
      </div>
    );
  }

  return (
    <SettingsLayout title="Paramètres" saving={saving}>
      <div className="space-y-8">
        <SettingsSection title="Général">
          <div className="flex items-center justify-between">
            <span className="text-sm text-muted">LM Studio</span>
            <Badge variant={health === "Connecté" ? "success" : "error"} dot>
              {health}
            </Badge>
          </div>
          <SettingsField label="Modèle par défaut">
            <Dropdown
              label="Modèle par défaut"
              value={settings.selectedModel}
              placement="bottom"
              menuFullWidth
              options={[
                { value: "", label: "— Sélectionner —" },
                ...models.map((m) => ({ value: m.id, label: m.id })),
              ]}
              onChange={(modelId) => save({ selectedModel: modelId })}
              triggerClassName={settingsSelectTriggerClass}
              className="w-full"
            />
          </SettingsField>
        </SettingsSection>

        <SettingsSection
          title="Génération"
          description="Le mode de raisonnement se configure dans le composer du chat."
        >
          <SettingsField label={`Température · ${settings.temperature}`}>
            <input
              type="range"
              min={0}
              max={2}
              step={0.1}
              value={settings.temperature}
              onChange={(e) => save({ temperature: parseFloat(e.target.value) })}
              className="w-full accent-accent"
            />
          </SettingsField>
          <SettingsField label="Max tokens">
            <input
              type="number"
              value={settings.maxTokens}
              onChange={(e) => save({ maxTokens: parseInt(e.target.value) })}
              className={settingsInputClass}
            />
          </SettingsField>
          <SettingsField label="Context length">
            <input
              type="number"
              value={settings.contextLength}
              onChange={(e) => save({ contextLength: parseInt(e.target.value) })}
              className={settingsInputClass}
            />
          </SettingsField>
        </SettingsSection>

        <SettingsSection title="System Prompt">
          <textarea
            value={settings.systemPrompt}
            onChange={(e) => setSettings({ ...settings, systemPrompt: e.target.value })}
            onBlur={() => save({ systemPrompt: settings.systemPrompt })}
            rows={6}
            className={`${settingsInputClass} resize-y`}
          />
        </SettingsSection>

        <SettingsSection title="Mémoire">
          <Switch
            checked={settings.memoryEnabled}
            onChange={(checked) => save({ memoryEnabled: checked })}
            label="Activer la mémoire"
            description="Permet à l'assistant de retenir des informations entre les conversations."
          />
          <div className="flex flex-wrap gap-2 pt-2">
            <Link href="/settings/memory">
              <Button variant="secondary" size="sm">
                Gérer les souvenirs
              </Button>
            </Link>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => void openExternal("/api/memories/export")}
            >
              Exporter JSON
            </Button>
          </div>
        </SettingsSection>

        <SettingsSection
          title="Recherche Web"
          description="Seule la requête de recherche est envoyée sur Internet."
        >
          <Switch
            checked={settings.webSearchEnabled}
            onChange={(checked) => save({ webSearchEnabled: checked })}
            label="Activer la recherche Web"
          />
          <SettingsField label="Max résultats">
            <input
              type="number"
              min={1}
              max={20}
              value={settings.webSearchMaxResults}
              onChange={(e) =>
                save({ webSearchMaxResults: parseInt(e.target.value) })
              }
              className={settingsInputClass}
            />
          </SettingsField>
          <SettingsField label="Timeout (ms)">
            <input
              type="number"
              value={settings.webSearchTimeoutMs}
              onChange={(e) =>
                save({ webSearchTimeoutMs: parseInt(e.target.value) })
              }
              className={settingsInputClass}
            />
          </SettingsField>
        </SettingsSection>

        <SettingsSection
          title="Email"
          description="Connectez Gmail pour lire et envoyer des emails depuis le chat."
        >
          <Link href="/settings/email">
            <Button variant="secondary" size="sm">
              Paramètres Gmail
            </Button>
          </Link>
        </SettingsSection>

        <SettingsSection
          title="Files"
          description="Dossiers locaux autorisés pour l'assistant documentaire."
        >
          <Link href="/settings/files">
            <Button variant="secondary" size="sm">
              Paramètres Files
            </Button>
          </Link>
        </SettingsSection>

        <SettingsSection
          title="Alimentation"
          description="Contrôle à distance du PC serveur (Cloudflare Access requis)."
        >
          <ShutdownPcPanel />
        </SettingsSection>

        <SettingsSection
          title="Test Wake-on-LAN"
          description="Temporaire — diagnostic POST /wake (à supprimer après validation)."
        >
          <WakeTestPanel />
        </SettingsSection>
      </div>
    </SettingsLayout>
  );
}
