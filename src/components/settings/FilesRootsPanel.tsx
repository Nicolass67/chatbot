"use client";

import { useCallback, useEffect, useState } from "react";
import { FolderOpen, Plus, Trash2 } from "lucide-react";
import { Badge } from "@/components/ui/Badge";
import { Button } from "@/components/ui/Button";
import { Spinner } from "@/components/ui/Spinner";
import { settingsInputClass } from "@/components/ui/SettingsLayout";

type Root = {
  id: string;
  label: string;
  absolutePath: string;
  enabled: boolean;
  isDefault: boolean;
};

export function FilesRootsPanel() {
  const [roots, setRoots] = useState<Root[]>([]);
  const [enabled, setEnabled] = useState(true);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [path, setPath] = useState("");
  const [label, setLabel] = useState("");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/files/roots");
      const data = (await res.json()) as {
        error?: string;
        roots?: Root[];
        enabled?: boolean;
      };
      if (!res.ok) {
        setEnabled(false);
        setError(data.error ?? "Files désactivé");
        setRoots([]);
        return;
      }
      setEnabled(true);
      setRoots(data.roots ?? []);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const addRoot = async () => {
    if (!path.trim()) return;
    setBusy(true);
    setError(null);
    try {
      const res = await fetch("/api/files/roots", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ absolutePath: path.trim(), label: label.trim() }),
      });
      const data = (await res.json()) as { error?: string };
      if (!res.ok) throw new Error(data.error ?? "Ajout échoué");
      setPath("");
      setLabel("");
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur");
    } finally {
      setBusy(false);
    }
  };

  const toggle = async (rootId: string, next: boolean) => {
    setBusy(true);
    try {
      const res = await fetch("/api/files/roots", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ rootId, enabled: next }),
      });
      if (!res.ok) {
        const data = (await res.json()) as { error?: string };
        throw new Error(data.error ?? "Échec");
      }
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur");
    } finally {
      setBusy(false);
    }
  };

  const remove = async (rootId: string) => {
    setBusy(true);
    try {
      const res = await fetch(`/api/files/roots?rootId=${encodeURIComponent(rootId)}`, {
        method: "DELETE",
      });
      if (!res.ok) {
        const data = (await res.json()) as { error?: string };
        throw new Error(data.error ?? "Échec");
      }
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur");
    } finally {
      setBusy(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center gap-2 py-4 text-muted">
        <Spinner />
        <span className="text-sm">Chargement…</span>
      </div>
    );
  }

  if (!enabled) {
    return (
      <p className="text-sm text-muted">
        Files est désactivé. Mettez <code>FILES_ENABLED=true</code> dans{" "}
        <code>.env</code> puis redémarrez le serveur.
      </p>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2 text-sm">
        <FolderOpen className="h-4 w-4 text-accent" />
        <Badge variant="muted">Actif</Badge>
        <span className="text-muted">
          Roots allowlist — Documents / Downloads créés automatiquement si absents.
        </span>
      </div>

      {error && <p className="text-sm text-red-600">{error}</p>}

      <ul className="space-y-2">
        {roots.map((root) => (
          <li
            key={root.id}
            className="flex flex-wrap items-center gap-2 rounded-lg border border-border-subtle px-3 py-2 text-sm"
          >
            <div className="min-w-0 flex-1">
              <p className="font-medium">{root.label}</p>
              <p className="truncate text-xs text-muted">{root.absolutePath}</p>
            </div>
            <Badge variant={root.enabled ? "success" : "muted"}>
              {root.enabled ? "on" : "off"}
            </Badge>
            <Button
              type="button"
              size="sm"
              variant="secondary"
              disabled={busy}
              onClick={() => void toggle(root.id, !root.enabled)}
            >
              {root.enabled ? "Désactiver" : "Activer"}
            </Button>
            <Button
              type="button"
              size="sm"
              variant="secondary"
              disabled={busy}
              onClick={() => void remove(root.id)}
            >
              <Trash2 className="h-3.5 w-3.5" />
            </Button>
          </li>
        ))}
      </ul>

      <div className="space-y-2 rounded-lg border border-border-subtle p-3">
        <p className="text-sm font-medium">Ajouter une root</p>
        <input
          className={settingsInputClass}
          placeholder="Libellé (ex. Desktop)"
          value={label}
          onChange={(e) => setLabel(e.target.value)}
        />
        <input
          className={settingsInputClass}
          placeholder="Chemin absolu Windows"
          value={path}
          onChange={(e) => setPath(e.target.value)}
        />
        <Button
          type="button"
          size="sm"
          disabled={busy || !path.trim()}
          onClick={() => void addRoot()}
        >
          <Plus className="h-3.5 w-3.5" />
          Ajouter
        </Button>
      </div>
    </div>
  );
}
