"use client";

import { useEffect, useMemo, useState } from "react";
import { AlertTriangle, FolderOpen, FolderPlus } from "lucide-react";
import { Button } from "@/components/ui/Button";
import { cn } from "@/lib/utils/cn";
import { FilesFolderPicker } from "@/components/files/FilesFolderPicker";

export type FilesMutationPending = {
  actionId: string;
  confirmationToken: string;
  expiresAt: string;
  op: "create_directory" | "rename_file" | "move_file";
  payload: {
    sourceRelativePath?: string;
    destRootId: string;
    destRelativePath: string;
  };
  notice?: string;
};

function opLabel(op: FilesMutationPending["op"], count: number): string {
  switch (op) {
    case "create_directory":
      return "Créer le dossier";
    case "rename_file":
      return "Renommer";
    case "move_file":
      return count > 1 ? `Déplacer ${count} éléments` : "Déplacer";
  }
}

function splitDestPath(destRelativePath: string): {
  parentPath: string;
  folderName: string;
} {
  const normalized = destRelativePath.replace(/\\/g, "/").replace(/^\/+|\/+$/g, "");
  if (!normalized) return { parentPath: "", folderName: "Nouveau dossier" };
  const idx = normalized.lastIndexOf("/");
  if (idx < 0) return { parentPath: "", folderName: normalized };
  return {
    parentPath: normalized.slice(0, idx),
    folderName: normalized.slice(idx + 1) || "Nouveau dossier",
  };
}

interface FilesMutationConfirmationProps {
  proposals: FilesMutationPending[];
  onDone: () => void;
  className?: string;
}

export function FilesMutationConfirmation({
  proposals,
  onDone,
  className,
}: FilesMutationConfirmationProps) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expired, setExpired] = useState(false);
  const [doneCount, setDoneCount] = useState(0);
  const [roots, setRoots] = useState<Array<{ id: string; label: string }>>([]);

  const first = proposals[0];
  const count = proposals.length;
  const isCreate = first?.op === "create_directory" && count === 1;

  const initialSplit = useMemo(
    () => (first ? splitDestPath(first.payload.destRelativePath) : null),
    [first]
  );

  const [editRootId, setEditRootId] = useState(first?.payload.destRootId ?? "");
  const [editParentPath, setEditParentPath] = useState(
    initialSplit?.parentPath ?? ""
  );
  const [editFolderName, setEditFolderName] = useState(
    initialSplit?.folderName ?? "Nouveau dossier"
  );

  useEffect(() => {
    if (!first) return;
    const split = splitDestPath(first.payload.destRelativePath);
    setEditRootId(first.payload.destRootId);
    setEditParentPath(split.parentPath);
    setEditFolderName(split.folderName);
  }, [first?.actionId]); // eslint-disable-line react-hooks/exhaustive-deps -- reset when proposal changes

  useEffect(() => {
    if (!isCreate) return;
    void (async () => {
      try {
        const res = await fetch("/api/files/roots");
        const data = (await res.json()) as {
          roots?: Array<{ id: string; label: string; enabled?: boolean }>;
        };
        setRoots(
          (data.roots ?? [])
            .filter((r) => r.enabled !== false)
            .map((r) => ({ id: r.id, label: r.label }))
        );
      } catch {
        setRoots([]);
      }
    })();
  }, [isCreate]);

  useEffect(() => {
    if (!first) return;
    const earliest = Math.min(
      ...proposals.map((p) => new Date(p.expiresAt).getTime())
    );
    const ms = earliest - Date.now();
    if (ms <= 0) {
      setExpired(true);
      return;
    }
    const timer = window.setTimeout(() => setExpired(true), ms);
    return () => window.clearTimeout(timer);
  }, [first, proposals]);

  if (!first || count === 0) return null;

  const builtDestPath = editParentPath
    ? `${editParentPath.replace(/\/+$/, "")}/${editFolderName.trim()}`
    : editFolderName.trim();

  const nameInvalid =
    !editFolderName.trim() ||
    /[\\/:*?"<>|]/.test(editFolderName) ||
    editFolderName === "." ||
    editFolderName === "..";

  const confirm = async () => {
    setBusy(true);
    setError(null);
    setDoneCount(0);
    try {
      if (isCreate) {
        if (nameInvalid) {
          throw new Error("Nom de dossier invalide.");
        }
        const changed =
          editRootId !== first.payload.destRootId ||
          builtDestPath !== first.payload.destRelativePath;

        let actionId = first.actionId;
        let confirmationToken = first.confirmationToken;

        if (changed) {
          // Annule l'ancienne proposition puis en crée une à jour.
          await fetch("/api/files/actions", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              action: "cancel",
              actionId: first.actionId,
            }),
          });
          const proposeRes = await fetch("/api/files/propose", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              op: "create_directory",
              destRootId: editRootId,
              destRelativePath: builtDestPath,
            }),
          });
          const proposed = (await proposeRes.json()) as FilesMutationPending & {
            error?: string;
          };
          if (!proposeRes.ok) {
            throw new Error(proposed.error ?? "Impossible de mettre à jour la destination");
          }
          actionId = proposed.actionId;
          confirmationToken = proposed.confirmationToken;
        }

        const res = await fetch("/api/files/actions", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            action: "confirm",
            actionId,
            confirmationToken,
          }),
        });
        const data = (await res.json()) as { error?: string };
        if (!res.ok) throw new Error(data.error ?? "Confirmation échouée");
        onDone();
        return;
      }

      for (let i = 0; i < proposals.length; i += 1) {
        const proposal = proposals[i]!;
        const res = await fetch("/api/files/actions", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            action: "confirm",
            actionId: proposal.actionId,
            confirmationToken: proposal.confirmationToken,
          }),
        });
        const data = (await res.json()) as { error?: string };
        if (!res.ok) {
          throw new Error(
            data.error ??
              `Confirmation échouée (${i + 1}/${proposals.length})`
          );
        }
        setDoneCount(i + 1);
      }
      onDone();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur");
    } finally {
      setBusy(false);
    }
  };

  const cancel = async () => {
    setBusy(true);
    setError(null);
    try {
      for (const proposal of proposals) {
        const res = await fetch("/api/files/actions", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            action: "cancel",
            actionId: proposal.actionId,
          }),
        });
        const data = (await res.json()) as { error?: string };
        if (!res.ok) {
          // Déjà annulée / confirmée : on ferme quand même la carte.
          if (!/introuvable|non annulable|ne peut plus/i.test(data.error ?? "")) {
            throw new Error(data.error ?? "Annulation échouée");
          }
        }
      }
      onDone();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur");
    } finally {
      setBusy(false);
    }
  };

  const sources = proposals
    .map((p) => p.payload.sourceRelativePath)
    .filter(Boolean) as string[];

  return (
    <div
      className={cn(
        "mb-3 rounded-[var(--radius-xl)] border border-amber-500/40 bg-amber-500/10 px-4 py-3",
        className
      )}
    >
      <div className="mb-2 flex items-center gap-2 text-sm font-medium">
        <AlertTriangle className="h-4 w-4 text-amber-600" />
        Confirmation requise — {opLabel(first.op, count)}
      </div>
      <div className="mb-3 space-y-2 text-sm text-muted">
        {sources.length === 1 && (
          <p>
            Source : <code className="text-xs">{sources[0]}</code>
          </p>
        )}
        {sources.length > 1 && (
          <div>
            <p className="mb-1">Sources ({sources.length}) :</p>
            <ul className="max-h-28 space-y-0.5 overflow-y-auto text-xs">
              {sources.map((s) => (
                <li key={s}>
                  <code>{s}</code>
                </li>
              ))}
            </ul>
          </div>
        )}

        {isCreate ? (
          <div className="space-y-3 rounded-[var(--radius-md)] border border-border-subtle bg-background/60 p-3">
            <label className="block text-xs font-medium text-foreground">
              Nom du dossier
              <input
                value={editFolderName}
                onChange={(e) => setEditFolderName(e.target.value)}
                className="mt-1 w-full rounded-[var(--radius-md)] border border-border-subtle bg-background px-3 py-2 text-sm text-foreground outline-none focus:border-border-strong"
                placeholder="Nouveau dossier"
                disabled={busy || expired}
              />
            </label>
            <div>
              <p className="mb-1.5 text-xs font-medium text-foreground">
                Destination
              </p>
              {roots.length > 0 ? (
                <FilesFolderPicker
                  roots={roots}
                  rootId={editRootId || roots[0]!.id}
                  path={editParentPath}
                  onRootChange={setEditRootId}
                  onPathChange={setEditParentPath}
                />
              ) : (
                <p className="text-xs text-muted">Chargement des dossiers…</p>
              )}
            </div>
            <p className="text-[11px] text-muted">
              Chemin final :{" "}
              <code className="text-[11px] text-foreground">
                {builtDestPath || "/"}
              </code>
            </p>
          </div>
        ) : (
          <p>
            Destination :{" "}
            <code className="text-xs">
              {count === 1
                ? first.payload.destRelativePath
                : first.payload.destRelativePath.includes("/")
                  ? first.payload.destRelativePath.slice(
                      0,
                      first.payload.destRelativePath.lastIndexOf("/")
                    ) || "/"
                  : "/"}
            </code>
          </p>
        )}

        {first.op === "create_directory" && (
          <p className="text-[11px] text-muted">
            Tu pourras supprimer ce dossier ensuite si besoin.
          </p>
        )}
        {first.op !== "create_directory" && (
          <p className="text-[11px] text-muted">
            Vérifie bien la destination avant de confirmer.
          </p>
        )}
        {first.notice &&
          !/non annulable/i.test(first.notice) && (
            <p>{first.notice}</p>
          )}
        {busy && count > 1 && doneCount > 0 && (
          <p>
            Progression : {doneCount}/{count}
          </p>
        )}
        {expired && <p className="text-error">Cette action a expiré.</p>}
        {error && <p className="text-error">{error}</p>}
      </div>
      <div className="flex flex-wrap gap-2">
        <Button
          type="button"
          size="sm"
          disabled={busy || expired || (isCreate && nameInvalid)}
          onClick={() => void confirm()}
        >
          {isCreate ? (
            <FolderPlus className="h-3.5 w-3.5" />
          ) : (
            <FolderOpen className="h-3.5 w-3.5" />
          )}
          Confirmer{count > 1 ? ` (${count})` : ""}
        </Button>
        <Button
          type="button"
          size="sm"
          variant="secondary"
          disabled={busy}
          onClick={() => void cancel()}
        >
          Annuler
        </Button>
      </div>
    </div>
  );
}
