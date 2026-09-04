"use client";

import { useState } from "react";
import { settingsInputClass } from "@/components/ui/SettingsLayout";
import { Button } from "@/components/ui/Button";
import type { EmailDraftPreview } from "@/lib/email/draft/types";
import type { UpdateDraftInput } from "@/lib/email/email-client";

interface DraftEditorProps {
  draft: EmailDraftPreview;
  disabled?: boolean;
  onSave: (patch: UpdateDraftInput) => Promise<void>;
  onCancel: () => void;
}

function joinAddresses(addresses: string[]): string {
  return addresses.join(", ");
}

function parseAddresses(value: string): string[] {
  return value
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
}

export function DraftEditor({
  draft,
  disabled,
  onSave,
  onCancel,
}: DraftEditorProps) {
  const [to, setTo] = useState(joinAddresses(draft.to));
  const [cc, setCc] = useState(joinAddresses(draft.cc));
  const [bcc, setBcc] = useState(joinAddresses(draft.bcc));
  const [subject, setSubject] = useState(draft.subject);
  const [bodyText, setBodyText] = useState(draft.bodyText);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    setSaving(true);
    setError(null);
    try {
      await onSave({
        to: parseAddresses(to),
        cc: parseAddresses(cc),
        bcc: parseAddresses(bcc),
        subject: subject.trim(),
        bodyText,
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Échec de la sauvegarde");
    } finally {
      setSaving(false);
    }
  };

  return (
    <form onSubmit={(e) => void handleSubmit(e)} className="space-y-3">
      <label className="block space-y-1">
        <span className="text-[11px] font-medium text-muted-foreground">À</span>
        <input
          value={to}
          onChange={(e) => setTo(e.target.value)}
          disabled={disabled || saving}
          className={settingsInputClass}
          placeholder="dest@example.com"
        />
      </label>
      <label className="block space-y-1">
        <span className="text-[11px] font-medium text-muted-foreground">Cc</span>
        <input
          value={cc}
          onChange={(e) => setCc(e.target.value)}
          disabled={disabled || saving}
          className={settingsInputClass}
        />
      </label>
      <label className="block space-y-1">
        <span className="text-[11px] font-medium text-muted-foreground">Cci</span>
        <input
          value={bcc}
          onChange={(e) => setBcc(e.target.value)}
          disabled={disabled || saving}
          className={settingsInputClass}
        />
      </label>
      <label className="block space-y-1">
        <span className="text-[11px] font-medium text-muted-foreground">Objet</span>
        <input
          value={subject}
          onChange={(e) => setSubject(e.target.value)}
          disabled={disabled || saving}
          className={settingsInputClass}
        />
      </label>
      <label className="block space-y-1">
        <span className="text-[11px] font-medium text-muted-foreground">Message</span>
        <textarea
          value={bodyText}
          onChange={(e) => setBodyText(e.target.value)}
          disabled={disabled || saving}
          rows={8}
          className={`${settingsInputClass} resize-y`}
        />
      </label>
      {error && (
        <p className="text-xs text-error" role="alert">
          {error}
        </p>
      )}
      <div className="flex flex-wrap gap-2">
        <Button type="submit" variant="primary" size="sm" loading={saving} disabled={disabled}>
          Enregistrer
        </Button>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          disabled={saving}
          onClick={onCancel}
        >
          Annuler
        </Button>
      </div>
    </form>
  );
}
