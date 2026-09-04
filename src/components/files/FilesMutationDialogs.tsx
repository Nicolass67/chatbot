"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/Button";
import { Dialog } from "@/components/ui/Dialog";
import { settingsInputClass } from "@/components/ui/SettingsLayout";
import { FilesFolderPicker } from "@/components/files/FilesFolderPicker";

interface CreateFolderDialogProps {
  open: boolean;
  parentPath: string;
  onClose: () => void;
  onSubmit: (name: string) => Promise<void>;
}

export function CreateFolderDialog({
  open,
  parentPath,
  onClose,
  onSubmit,
}: CreateFolderDialogProps) {
  const [name, setName] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const invalid =
    !name.trim() ||
    /[\\/:*?"<>|]/.test(name) ||
    name === "." ||
    name === "..";

  const submit = async () => {
    if (invalid) {
      setError("Nom invalide pour Windows.");
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await onSubmit(name.trim());
      setName("");
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur");
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog
      open={open}
      title="Nouveau dossier"
      onClose={() => {
        if (!busy) onClose();
      }}
      footer={
        <>
          <Button type="button" variant="ghost" disabled={busy} onClick={onClose}>
            Annuler
          </Button>
          <Button
            type="button"
            variant="primary"
            loading={busy}
            disabled={invalid}
            onClick={() => void submit()}
          >
            Créer
          </Button>
        </>
      }
    >
      <p className="mb-3 text-xs text-muted">
        Emplacement : {parentPath || "(racine)"}
      </p>
      <label className="block text-sm">
        Nom
        <input
          className={settingsInputClass + " mt-1"}
          value={name}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") void submit();
          }}
          placeholder="Nouveau dossier"
        />
      </label>
      {error && <p className="mt-2 text-sm text-error">{error}</p>}
    </Dialog>
  );
}

interface RenameDialogProps {
  open: boolean;
  currentName: string;
  onClose: () => void;
  onSubmit: (newName: string) => Promise<void>;
}

export function RenameDialog({
  open,
  currentName,
  onClose,
  onSubmit,
}: RenameDialogProps) {
  const [name, setName] = useState(currentName);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setName(currentName);
      setError(null);
    }
  }, [open, currentName]);

  const invalid =
    !name.trim() ||
    /[\\/:*?"<>|]/.test(name) ||
    name === "." ||
    name === "..";

  return (
    <Dialog
      open={open}
      title="Renommer"
      onClose={() => {
        if (!busy) onClose();
      }}
      footer={
        <>
          <Button type="button" variant="ghost" disabled={busy} onClick={onClose}>
            Annuler
          </Button>
          <Button
            type="button"
            variant="primary"
            loading={busy}
            disabled={invalid || name.trim() === currentName}
            onClick={() => {
              void (async () => {
                setBusy(true);
                setError(null);
                try {
                  await onSubmit(name.trim());
                  onClose();
                } catch (err) {
                  setError(err instanceof Error ? err.message : "Erreur");
                } finally {
                  setBusy(false);
                }
              })();
            }}
          >
            Renommer
          </Button>
        </>
      }
    >
      <label className="block text-sm">
        Nouveau nom
        <input
          className={settingsInputClass + " mt-1"}
          value={name}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              (e.target as HTMLInputElement).blur();
            }
          }}
        />
      </label>
      {error && <p className="mt-2 text-sm text-error">{error}</p>}
    </Dialog>
  );
}

interface MoveDialogProps {
  open: boolean;
  itemCount: number;
  roots: Array<{ id: string; label: string }>;
  defaultRootId: string;
  defaultPath: string;
  onClose: () => void;
  onSubmit: (destRootId: string, destRelativePath: string) => Promise<void>;
}

export function MoveDialog({
  open,
  itemCount,
  roots,
  defaultRootId,
  defaultPath,
  onClose,
  onSubmit,
}: MoveDialogProps) {
  const [rootId, setRootId] = useState(defaultRootId);
  const [path, setPath] = useState(defaultPath);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setRootId(defaultRootId);
      setPath(defaultPath);
      setError(null);
    }
  }, [open, defaultRootId, defaultPath]);

  return (
    <Dialog
      open={open}
      title={`Déplacer ${itemCount} élément${itemCount > 1 ? "s" : ""}`}
      onClose={() => {
        if (!busy) onClose();
      }}
      footer={
        <>
          <Button type="button" variant="ghost" disabled={busy} onClick={onClose}>
            Annuler
          </Button>
          <Button
            type="button"
            variant="primary"
            loading={busy}
            onClick={() => {
              void (async () => {
                setBusy(true);
                setError(null);
                try {
                  await onSubmit(
                    rootId,
                    path.replace(/\\/g, "/").replace(/^\/+|\/+$/g, "")
                  );
                  onClose();
                } catch (err) {
                  setError(err instanceof Error ? err.message : "Erreur");
                } finally {
                  setBusy(false);
                }
              })();
            }}
          >
            Déplacer ici
          </Button>
        </>
      }
    >
      <FilesFolderPicker
        roots={roots}
        rootId={rootId}
        path={path}
        onRootChange={setRootId}
        onPathChange={setPath}
      />
      <p className="mt-2 text-xs text-muted">
        Sélectionne un dossier ci-dessus. Le nom du fichier sera conservé.
        Confirmation requise ensuite.
      </p>
      {error && <p className="mt-2 text-sm text-error">{error}</p>}
    </Dialog>
  );
}

interface UploadDialogProps {
  open: boolean;
  files: File[];
  roots: Array<{ id: string; label: string }>;
  defaultRootId: string;
  defaultPath: string;
  onClose: () => void;
  onSubmit: (destRootId: string, destRelativePath: string, files: File[]) => Promise<void>;
}

export function UploadDialog({
  open,
  files,
  roots,
  defaultRootId,
  defaultPath,
  onClose,
  onSubmit,
}: UploadDialogProps) {
  const [rootId, setRootId] = useState(defaultRootId);
  const [path, setPath] = useState(defaultPath);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) {
      setRootId(defaultRootId);
      setPath(defaultPath);
      setError(null);
    }
  }, [open, defaultRootId, defaultPath]);

  return (
    <Dialog
      open={open}
      title={`Enregistrer ${files.length} fichier${files.length > 1 ? "s" : ""}`}
      onClose={() => {
        if (!busy) onClose();
      }}
      footer={
        <>
          <Button type="button" variant="ghost" disabled={busy} onClick={onClose}>
            Annuler
          </Button>
          <Button
            type="button"
            variant="primary"
            loading={busy}
            disabled={files.length === 0}
            onClick={() => {
              void (async () => {
                setBusy(true);
                setError(null);
                try {
                  await onSubmit(
                    rootId,
                    path.replace(/\\/g, "/").replace(/^\/+|\/+$/g, ""),
                    files
                  );
                  onClose();
                } catch (err) {
                  setError(err instanceof Error ? err.message : "Erreur");
                } finally {
                  setBusy(false);
                }
              })();
            }}
          >
            Enregistrer ici
          </Button>
        </>
      }
    >
      <ul className="mb-3 max-h-24 space-y-1 overflow-y-auto text-xs text-muted">
        {files.map((f) => (
          <li key={`${f.name}-${f.size}`} className="truncate">
            {f.name} · {(f.size / 1024).toFixed(f.size > 1024 * 1024 ? 0 : 1)}
            {f.size > 1024 * 1024 ? " Mo" : " Ko"}
          </li>
        ))}
      </ul>
      <FilesFolderPicker
        roots={roots}
        rootId={rootId}
        path={path}
        onRootChange={setRootId}
        onPathChange={setPath}
      />
      {error && <p className="mt-2 text-sm text-error">{error}</p>}
    </Dialog>
  );
}
