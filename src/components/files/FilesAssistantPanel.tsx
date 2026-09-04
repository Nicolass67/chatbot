"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  Eye,
  File,
  Folder,
  FolderOpen,
  Send,
  X,
} from "lucide-react";
import { createPortal } from "react-dom";
import { IconButton } from "@/components/ui/IconButton";
import { Spinner } from "@/components/ui/Spinner";
import { cn } from "@/lib/utils/cn";
import {
  FilesMutationConfirmation,
  type FilesMutationPending,
} from "@/components/files/FilesMutationConfirmation";
import { formatBytes } from "@/components/files/types";
import { ModelSelector, type ModelOption } from "@/components/chat/ModelSelector";
import { HeaderStatusCluster } from "@/components/layout/HeaderStatusCluster";
import { isSelectableChatModel } from "@/lib/models/chat-models";
import type {
  ModelRuntimeSnapshot,
  RuntimeStatus,
} from "@/lib/runtime/types";

export type FilesAssistantFileCard = {
  fileId: string;
  name: string;
  relativePath: string;
  rootId: string;
  isDirectory: boolean;
  sizeBytes?: number;
  snippet?: string;
};

type ChatMessage = {
  id: string;
  role: "user" | "assistant";
  content: string;
  files?: FilesAssistantFileCard[];
  mutation?: FilesMutationPending;
};

interface FilesAssistantPanelProps {
  rootId: string;
  rootLabel: string;
  currentPath: string;
  selectedFileIds: string[];
  /** Ouvre uniquement l'aperçu (sans changer de dossier). */
  onPreviewFile: (file: FilesAssistantFileCard) => void;
  /** Navigue vers le dossier parent et sélectionne le fichier (sans aperçu). */
  onRevealFile: (file: FilesAssistantFileCard) => void;
  onMutationDone?: () => void;
  seedMessage?: string | null;
  onSeedConsumed?: () => void;
  /** Fichiers collés / déposés → parent ouvre la boîte d'enregistrement (après réponse IA). */
  onExternalFilesDrop?: (files: File[], destRelativePath?: string) => void;
}

export function FilesAssistantPanel({
  rootId,
  rootLabel,
  currentPath,
  selectedFileIds,
  onPreviewFile,
  onRevealFile,
  onMutationDone,
  seedMessage,
  onSeedConsumed,
  onExternalFilesDrop,
}: FilesAssistantPanelProps) {
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      id: "welcome",
      role: "assistant",
      content: `Je peux chercher des fichiers dans ${rootLabel}, répondre à des questions sur ce dossier, proposer des opérations (ex. nouveau dossier), et te donner un fichier à ouvrir ici.`,
    },
  ]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [models, setModels] = useState<ModelOption[]>([]);
  const [selectedModel, setSelectedModel] = useState("");
  const [modelsLoading, setModelsLoading] = useState(true);
  const [runtimeStatus, setRuntimeStatus] = useState<RuntimeStatus>("READY");
  const [modelRuntime, setModelRuntime] =
    useState<ModelRuntimeSnapshot | null>(null);
  const [dragOver, setDragOver] = useState(false);
  const [pendingPasteFiles, setPendingPasteFiles] = useState<File[]>([]);
  const [fileActionTarget, setFileActionTarget] =
    useState<FilesAssistantFileCard | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);
  const seedHandled = useRef<string | null>(null);

  const addPendingFiles = useCallback((files: FileList | File[]) => {
    const next = Array.from(files).filter((f) => f.size >= 0);
    if (next.length === 0) return;
    setPendingPasteFiles((prev) => {
      const seen = new Set(
        prev.map((f) => `${f.name}:${f.size}:${f.lastModified}`)
      );
      const merged = [...prev];
      for (const f of next) {
        const key = `${f.name}:${f.size}:${f.lastModified}`;
        if (seen.has(key)) continue;
        seen.add(key);
        merged.push(f);
      }
      return merged;
    });
  }, []);

  const removePendingFile = useCallback((index: number) => {
    setPendingPasteFiles((prev) => prev.filter((_, i) => i !== index));
  }, []);

  const handlePaste = (e: React.ClipboardEvent) => {
    const pasted: File[] = [];
    for (const item of e.clipboardData.items) {
      if (item.kind !== "file") continue;
      const file = item.getAsFile();
      if (file) pasted.push(file);
    }
    if (pasted.length === 0 && e.clipboardData.files.length > 0) {
      pasted.push(...Array.from(e.clipboardData.files));
    }
    if (pasted.length === 0) return;
    e.preventDefault();
    addPendingFiles(pasted);
  };

  const refreshRuntimeStatus = useCallback(async () => {
    try {
      const { cachedGetJson } = await import("@/lib/client/fetch-cache");
      const res = await cachedGetJson<{
        status?: RuntimeStatus;
        model?: ModelRuntimeSnapshot;
      }>("/api/runtime/status", { ttlMs: 5_000 });
      if (!res.ok) return;
      if (res.data.status) setRuntimeStatus(res.data.status);
      if (res.data.model) setModelRuntime(res.data.model);
    } catch {
      /* ignore */
    }
  }, []);

  useEffect(() => {
    void (async () => {
      try {
        const { cachedGetJson } = await import("@/lib/client/fetch-cache");
        const [modelsRes, statusRes] = await Promise.all([
          cachedGetJson<{ data?: { id: string; name?: string }[] }>(
            "/api/lm-studio/models",
            { ttlMs: 60_000 }
          ),
          cachedGetJson<{
            status?: RuntimeStatus;
            model?: ModelRuntimeSnapshot;
          }>("/api/runtime/status", { ttlMs: 5_000 }),
        ]);
        const modelsData = modelsRes.data;
        const statusData = statusRes.data;
        const opts =
          modelsData?.data
            ?.filter((m) => isSelectableChatModel(m.id, m.name))
            .map((m) => ({
              id: m.id,
              label: m.name ?? m.id.split("/").pop() ?? m.id,
            })) ?? [];
        setModels(opts);
        if (statusData?.status) setRuntimeStatus(statusData.status);
        if (statusData?.model) setModelRuntime(statusData.model);
        const preferred =
          statusData?.model?.preferredModel ??
          statusData?.model?.loadedModel ??
          opts[0]?.id ??
          "";
        const safePreferred = opts.some((o) => o.id === preferred)
          ? preferred
          : statusData?.model?.loadedModel &&
              opts.some((o) => o.id === statusData.model?.loadedModel)
            ? statusData.model.loadedModel
            : opts[0]?.id ?? "";
        setSelectedModel(safePreferred);
      } finally {
        setModelsLoading(false);
      }
    })();
  }, []);

  useEffect(() => {
    const phase = modelRuntime?.phase;
    if (phase !== "loading" && phase !== "unloading") return;
    const interval = window.setInterval(() => {
      void refreshRuntimeStatus();
    }, 1200);
    return () => window.clearInterval(interval);
  }, [modelRuntime?.phase, refreshRuntimeStatus]);

  const modelSwitching =
    modelRuntime?.phase === "loading" ||
    modelRuntime?.phase === "unloading" ||
    runtimeStatus === "LOADING_MODEL";

  const activeModelLabel =
    models.find((m) => m.id === selectedModel)?.label ?? selectedModel;

  const aiReady =
    runtimeStatus === "READY" || runtimeStatus === "BUSY";

  const handleModelChange = async (modelId: string) => {
    const previous =
      modelRuntime?.loadedModel &&
      models.some((m) => m.id === modelRuntime.loadedModel)
        ? modelRuntime.loadedModel
        : selectedModel;
    setSelectedModel(modelId);
    setError(null);
    setModelRuntime((prev) =>
      prev
        ? {
            ...prev,
            phase: "loading",
            targetModel: modelId,
            preferredModel: modelId,
            message: "Chargement…",
            error: undefined,
          }
        : {
            phase: "loading",
            preferredModel: modelId,
            loadedModel: null,
            targetModel: modelId,
            message: "Chargement…",
            pendingRequestCount: 0,
          }
    );
    setRuntimeStatus("LOADING_MODEL");
    try {
      const res = await fetch("/api/runtime/model", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ modelKey: modelId }),
      });
      if (!(res.status === 202 || res.ok)) {
        throw new Error("Impossible de demander le chargement du modèle");
      }
      // Attendre ready / error (le switch est async côté serveur)
      for (let i = 0; i < 60; i++) {
        await new Promise((r) => setTimeout(r, 500));
        const st = await fetch("/api/runtime/status");
        if (!st.ok) continue;
        const data = (await st.json()) as {
          status?: RuntimeStatus;
          model?: ModelRuntimeSnapshot;
        };
        if (data.status) setRuntimeStatus(data.status);
        if (data.model) setModelRuntime(data.model);
        const phase = data.model?.phase;
        if (phase === "ready" && data.model?.loadedModel === modelId) {
          setRuntimeStatus("READY");
          return;
        }
        if (phase === "error") {
          const msg =
            data.model?.error ||
            data.model?.message ||
            "Échec de chargement du modèle";
          setSelectedModel(previous);
          setError(
            `Impossible de charger ce modèle (${modelId.split("/").pop()}). ${msg}. Réessai avec le modèle actuel.`
          );
          setRuntimeStatus(
            data.model?.loadedModel ? "READY" : "ERROR"
          );
          return;
        }
      }
      setError("Chargement du modèle trop long — vérifie LM Studio.");
      setSelectedModel(previous);
      void refreshRuntimeStatus();
    } catch (err) {
      setSelectedModel(previous);
      setError(
        err instanceof Error ? err.message : "Erreur de changement de modèle"
      );
      void refreshRuntimeStatus();
    }
  };

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages, busy]);

  const effectiveModel =
    modelRuntime?.phase === "ready" && modelRuntime.loadedModel
      ? modelRuntime.loadedModel
      : modelRuntime?.loadedModel && selectedModel !== modelRuntime.loadedModel
        ? modelRuntime.loadedModel
        : selectedModel;

  const send = async (raw: string) => {
    const trimmed = raw.trim();
    const staged = pendingPasteFiles;
    if (
      (!trimmed && staged.length === 0) ||
      busy ||
      !rootId ||
      modelSwitching
    ) {
      return;
    }
    setError(null);
    setInput("");

    const messageText =
      trimmed ||
      (staged.length > 0
        ? `Enregistre ${staged.map((f) => f.name).join(", ")} dans le dossier courant`
        : "");

    const userMsg: ChatMessage = {
      id: `u-${Date.now()}`,
      role: "user",
      content:
        staged.length > 0
          ? `${messageText}\n\n📎 ${staged.map((f) => f.name).join(", ")}`
          : messageText,
    };
    setMessages((prev) => [...prev, userMsg]);
    setBusy(true);
    try {
      const res = await fetch("/api/files/ai/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: messageText,
          rootId,
          currentPath,
          selectedFileIds,
          model: effectiveModel || undefined,
          pendingUploads:
            staged.length > 0
              ? staged.map((f) => ({ name: f.name, sizeBytes: f.size }))
              : undefined,
        }),
      });
      const data = (await res.json()) as {
        reply?: string;
        files?: FilesAssistantFileCard[];
        mutation?: FilesMutationPending;
        uploadProposal?: {
          destRootId: string;
          destRelativePath: string;
          fileNames: string[];
        };
        error?: string;
      };
      if (!res.ok) {
        const errText = data.error ?? "Assistant indisponible";
        if (/failed to load model|invalid_request_error/i.test(errText)) {
          throw new Error(
            "Le modèle demandé n'est pas chargeable dans LM Studio. Choisis un autre modèle dans la liste (évite les variantes MTP / embedding)."
          );
        }
        throw new Error(errText);
      }
      setMessages((prev) => [
        ...prev,
        {
          id: `a-${Date.now()}`,
          role: "assistant",
          content: data.reply ?? "",
          files: data.files,
          mutation: data.mutation,
        },
      ]);

      // Après la réponse IA : ouvrir le sélecteur avec la destination proposée
      if (staged.length > 0 && data.uploadProposal) {
        setPendingPasteFiles([]);
        onExternalFilesDrop?.(
          staged,
          data.uploadProposal.destRelativePath
        );
      } else if (staged.length > 0) {
        // Fallback si l'IA n'a pas renvoyé de proposition
        setPendingPasteFiles([]);
        onExternalFilesDrop?.(staged);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur");
    } finally {
      setBusy(false);
    }
  };

  useEffect(() => {
    if (!seedMessage || seedHandled.current === seedMessage) return;
    seedHandled.current = seedMessage;
    onSeedConsumed?.();
    void send(seedMessage);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- seed one-shot
  }, [seedMessage]);

  return (
    <div
      className={cn(
        "relative flex h-full min-h-0 flex-col bg-surface",
        dragOver && "ring-2 ring-inset ring-accent"
      )}
      onDragEnter={(e) => {
        if (![...e.dataTransfer.types].includes("Files")) return;
        e.preventDefault();
        setDragOver(true);
      }}
      onDragOver={(e) => {
        if (![...e.dataTransfer.types].includes("Files")) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = "copy";
      }}
      onDragLeave={(e) => {
        if (e.currentTarget === e.target) setDragOver(false);
      }}
      onDrop={(e) => {
        e.preventDefault();
        setDragOver(false);
        const list = [...e.dataTransfer.files];
        if (list.length) addPendingFiles(list);
      }}
    >
      <div className="flex shrink-0 flex-col gap-1.5 border-b border-border-subtle px-3 py-2">
        <div className="flex min-w-0 items-start justify-between gap-2">
          <HeaderStatusCluster
            runtimeStatus={runtimeStatus}
            modelRuntime={modelRuntime}
            activeModelLabel={activeModelLabel}
            showWeb={false}
            align="start"
            className="min-w-0"
          />
          <ModelSelector
            models={models}
            value={selectedModel}
            loading={modelsLoading}
            switching={modelSwitching}
            switchingLabel={modelRuntime?.message ?? "Chargement…"}
            disabled={busy || modelSwitching}
            onChange={(id) => void handleModelChange(id)}
            placement="bottom"
            className="min-w-0 shrink-0"
          />
        </div>
        {!aiReady && !modelsLoading && !modelSwitching && (
          <p className="rounded-[var(--radius-md)] bg-warning/10 px-2.5 py-1.5 text-xs text-warning">
            IA indisponible — choisis un modèle ou vérifie LM Studio.
          </p>
        )}
      </div>

      {dragOver && (
        <div className="pointer-events-none absolute inset-0 z-10 flex items-center justify-center bg-accent/10 text-sm font-medium text-foreground">
          Déposer pour joindre à l’assistant…
        </div>
      )}

      <div className="min-h-0 flex-1 space-y-3 overflow-y-auto px-3 py-3">
        <p className="text-[11px] text-muted">
          Contexte : {rootLabel}
          {currentPath ? ` / ${currentPath}` : ""}
          {selectedFileIds.length > 0
            ? ` · ${selectedFileIds.length} sélectionné${selectedFileIds.length > 1 ? "s" : ""}`
            : ""}
        </p>

        {messages.map((m) => (
          <div
            key={m.id}
            className={cn(
              "max-w-[95%] rounded-[var(--radius-lg)] px-3 py-2 text-sm",
              m.role === "user"
                ? "ml-auto bg-accent/20 text-foreground"
                : "mr-auto bg-surface-elevated text-foreground"
            )}
          >
            <p className="whitespace-pre-wrap break-words">{m.content}</p>
            {m.files && m.files.length > 0 && (
              <ul className="mt-2 space-y-1.5">
                {m.files.map((f) => {
                  const Icon = f.isDirectory ? Folder : File;
                  return (
                    <li key={f.fileId}>
                      <button
                        type="button"
                        onClick={() => {
                          if (f.isDirectory) {
                            onRevealFile(f);
                            return;
                          }
                          setFileActionTarget(f);
                        }}
                        className="flex w-full items-start gap-2 rounded-[var(--radius-md)] border border-border-subtle bg-background px-2.5 py-2 text-left transition-colors hover:border-accent/40 hover:bg-surface-hover"
                      >
                        <Icon
                          className={cn(
                            "mt-0.5 h-4 w-4 shrink-0",
                            f.isDirectory ? "text-accent" : "text-muted"
                          )}
                        />
                        <span className="min-w-0 flex-1">
                          <span className="block truncate text-sm font-medium">
                            {f.name}
                          </span>
                          <span className="block truncate text-[11px] text-muted">
                            {f.relativePath}
                            {typeof f.sizeBytes === "number" && !f.isDirectory
                              ? ` · ${formatBytes(f.sizeBytes)}`
                              : ""}
                          </span>
                          {f.snippet && (
                            <span className="mt-0.5 block line-clamp-2 text-[11px] text-muted">
                              {f.snippet}
                            </span>
                          )}
                        </span>
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
            {m.mutation && (
              <div className="mt-2">
                <FilesMutationConfirmation
                  proposals={[m.mutation]}
                  onDone={() => {
                    onMutationDone?.();
                    setMessages((prev) =>
                      prev.map((x) =>
                        x.id === m.id ? { ...x, mutation: undefined } : x
                      )
                    );
                  }}
                />
              </div>
            )}
          </div>
        ))}

        {busy && (
          <div className="flex items-center gap-2 text-xs text-muted">
            <Spinner size="sm" />
            L’assistant réfléchit…
          </div>
        )}
        {error && <p className="text-sm text-error">{error}</p>}
        <div ref={bottomRef} />
      </div>

      <div className="shrink-0 border-t border-border-subtle px-3 py-2">
        {selectedFileIds.length > 0 && (
          <div className="mb-2 flex flex-wrap gap-1.5">
            <button
              type="button"
              disabled={busy || modelSwitching}
              onClick={() =>
                void send("Analyse le fichier sélectionné et résume-le.")
              }
              className="inline-flex items-center gap-1 rounded-[var(--radius-sm)] bg-surface-hover px-2 py-1 text-[11px] text-foreground hover:bg-surface-active disabled:opacity-50"
            >
              Analyser la sélection
            </button>
          </div>
        )}
        {pendingPasteFiles.length > 0 && (
          <div className="mb-2 space-y-1.5">
            <ul className="flex flex-wrap gap-1.5">
              {pendingPasteFiles.map((f, index) => (
                <li
                  key={`${f.name}-${f.size}-${f.lastModified}-${index}`}
                  className="inline-flex max-w-full items-center gap-1 rounded-[var(--radius-md)] border border-border-subtle bg-background px-2 py-1 text-[11px] text-foreground"
                >
                  <File className="h-3 w-3 shrink-0 text-muted" />
                  <span className="min-w-0 truncate" title={f.name}>
                    {f.name}
                  </span>
                  <span className="shrink-0 text-muted">
                    {formatBytes(f.size)}
                  </span>
                  <button
                    type="button"
                    className="shrink-0 rounded p-0.5 text-muted hover:bg-surface-hover hover:text-foreground"
                    aria-label={`Retirer ${f.name}`}
                    onClick={() => removePendingFile(index)}
                  >
                    <X className="h-3 w-3" />
                  </button>
                </li>
              ))}
            </ul>
            <p className="text-[11px] text-muted">
              Indique où enregistrer (ex. « mets ça à la racine »), puis
              Envoyer — l’IA propose la destination, ensuite tu confirmes.
            </p>
          </div>
        )}
        <form
          className="flex items-end gap-1.5"
          onSubmit={(e) => {
            e.preventDefault();
            void send(input);
          }}
        >
          <textarea
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onPaste={handlePaste}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                void send(input);
              }
            }}
            rows={2}
            placeholder={
              pendingPasteFiles.length > 0
                ? "Où enregistrer ces fichiers ?"
                : "Cherche un fichier, pose une question… (Ctrl+V pour coller)"
            }
            className="min-h-[2.5rem] flex-1 resize-none rounded-[var(--radius-md)] border border-border-subtle bg-background px-3 py-2 text-sm outline-none focus:border-border-strong"
            disabled={busy || modelSwitching}
          />
          <IconButton
            label="Envoyer"
            size="md"
            variant="primary"
            disabled={
              busy ||
              modelSwitching ||
              (!input.trim() && pendingPasteFiles.length === 0)
            }
            onClick={() => void send(input)}
          >
            <Send className="h-4 w-4" />
          </IconButton>
        </form>
        <p className="mt-1.5 text-[10px] text-muted">
          Les mutations requièrent toujours une confirmation.
        </p>
      </div>

      {fileActionTarget &&
        typeof document !== "undefined" &&
        createPortal(
          <div className="fixed inset-0 z-[120] flex items-end justify-center sm:items-center sm:p-4">
            <button
              type="button"
              className="absolute inset-0 bg-black/55"
              aria-label="Fermer"
              onClick={() => setFileActionTarget(null)}
            />
            <div
              role="dialog"
              aria-modal="true"
              aria-label={`Ouvrir ${fileActionTarget.name}`}
              className={cn(
                "relative z-10 w-full max-w-md overflow-hidden rounded-t-[1.25rem] border border-border-subtle bg-surface shadow-[var(--shadow-popover)] sm:rounded-[1.25rem]"
              )}
            >
              <div className="flex items-start justify-between gap-2 border-b border-border-subtle px-4 py-3">
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold text-foreground">
                    {fileActionTarget.name}
                  </p>
                  <p className="truncate text-[11px] text-muted">
                    {fileActionTarget.relativePath}
                  </p>
                </div>
                <IconButton
                  variant="ghost"
                  size="sm"
                  label="Fermer"
                  onClick={() => setFileActionTarget(null)}
                >
                  <X className="h-4 w-4" />
                </IconButton>
              </div>
              <div className="flex flex-col p-2 pb-[max(0.5rem,env(safe-area-inset-bottom))]">
                <button
                  type="button"
                  className="flex min-h-12 items-center gap-3 rounded-[var(--radius-md)] px-3 py-2.5 text-left text-sm text-foreground hover:bg-surface-hover"
                  onClick={() => {
                    const target = fileActionTarget;
                    setFileActionTarget(null);
                    onPreviewFile(target);
                  }}
                >
                  <Eye className="h-4 w-4 shrink-0 text-accent" />
                  <span>
                    <span className="block font-medium">Afficher</span>
                    <span className="block text-[11px] text-muted">
                      Ouvrir l’aperçu sans changer de dossier
                    </span>
                  </span>
                </button>
                <button
                  type="button"
                  className="flex min-h-12 items-center gap-3 rounded-[var(--radius-md)] px-3 py-2.5 text-left text-sm text-foreground hover:bg-surface-hover"
                  onClick={() => {
                    const target = fileActionTarget;
                    setFileActionTarget(null);
                    onRevealFile(target);
                  }}
                >
                  <FolderOpen className="h-4 w-4 shrink-0 text-accent" />
                  <span>
                    <span className="block font-medium">
                      Aller à la destination
                    </span>
                    <span className="block text-[11px] text-muted">
                      Ouvrir le dossier et sélectionner le fichier
                    </span>
                  </span>
                </button>
              </div>
            </div>
          </div>,
          document.body
        )}
    </div>
  );
}
