"use client";

import { useEffect, useState } from "react";
import { Trash2 } from "lucide-react";
import {
  SettingsLayout,
  settingsInputClass,
} from "@/components/ui/SettingsLayout";
import { Button } from "@/components/ui/Button";
import { IconButton } from "@/components/ui/IconButton";
import { Badge } from "@/components/ui/Badge";
import { Spinner } from "@/components/ui/Spinner";

interface Memory {
  id: string;
  content: string;
  category: string;
  importance: number;
  updatedAt: string;
}

export default function MemorySettingsPage() {
  const [memories, setMemories] = useState<Memory[]>([]);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [confirmDeleteAll, setConfirmDeleteAll] = useState(false);

  const load = async (q?: string) => {
    setLoading(true);
    const url = q ? `/api/memories?q=${encodeURIComponent(q)}` : "/api/memories";
    const res = await fetch(url);
    if (res.ok) setMemories(await res.json());
    setLoading(false);
  };

  useEffect(() => {
    void load();
  }, []);

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    void load(query);
  };

  const handleDelete = async (id: string) => {
    await fetch(`/api/memories/${id}`, { method: "DELETE" });
    void load(query || undefined);
  };

  const handleDeleteAll = async () => {
    if (!confirmDeleteAll) {
      setConfirmDeleteAll(true);
      setTimeout(() => setConfirmDeleteAll(false), 3000);
      return;
    }
    await fetch("/api/memories", { method: "DELETE" });
    setConfirmDeleteAll(false);
    void load();
  };

  const handleImport = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    const text = await file.text();
    const data = JSON.parse(text);
    const imported = Array.isArray(data) ? data : data.memories;
    await fetch("/api/memories/import", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ mode: "merge", memories: imported }),
    });
    void load();
  };

  return (
    <SettingsLayout title="Mémoire" backHref="/settings">
      <div className="space-y-6">
        <form onSubmit={handleSearch} className="flex gap-2">
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Rechercher un souvenir…"
            className={`${settingsInputClass} flex-1`}
          />
          <Button type="submit" variant="primary" size="md">
            Rechercher
          </Button>
        </form>

        <div className="flex flex-wrap gap-2">
          <Button
            type="button"
            variant={confirmDeleteAll ? "danger" : "secondary"}
            size="sm"
            onClick={() => void handleDeleteAll()}
          >
            {confirmDeleteAll ? "Confirmer la suppression" : "Tout supprimer"}
          </Button>
          <label className="inline-flex cursor-pointer items-center rounded-[var(--radius-md)] border border-border bg-surface-elevated px-3 py-1.5 text-sm font-medium text-foreground transition-colors hover:bg-surface-hover">
            Importer JSON
            <input
              type="file"
              accept=".json"
              onChange={handleImport}
              className="hidden"
            />
          </label>
        </div>

        {loading ? (
          <div className="flex items-center justify-center gap-2 py-12 text-muted">
            <Spinner />
            <span className="text-sm">Chargement…</span>
          </div>
        ) : memories.length === 0 ? (
          <p className="py-12 text-center text-sm text-muted-foreground">
            Aucun souvenir enregistré
          </p>
        ) : (
          <ul className="space-y-3">
            {memories.map((m) => (
              <li
                key={m.id}
                className="rounded-[var(--radius-xl)] border border-border-subtle bg-surface p-4"
              >
                <div className="mb-2 flex items-start justify-between gap-2">
                  <div className="flex flex-wrap gap-1.5">
                    <Badge variant="default">{m.category}</Badge>
                    <Badge variant="muted">{m.importance.toFixed(1)}</Badge>
                  </div>
                  <IconButton
                    size="sm"
                    label="Supprimer"
                    onClick={() => void handleDelete(m.id)}
                    className="h-7 w-7 text-muted hover:text-error"
                  >
                    <Trash2 className="h-3.5 w-3.5" />
                  </IconButton>
                </div>
                <p className="text-sm leading-relaxed text-foreground">{m.content}</p>
              </li>
            ))}
          </ul>
        )}
      </div>
    </SettingsLayout>
  );
}
