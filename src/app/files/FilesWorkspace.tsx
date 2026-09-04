"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useToast } from "@/components/ui/Toast";
import { FilesLayout } from "@/components/files/FilesLayout";
import { FilesRootsNav } from "@/components/files/FilesRootsNav";
import { FilesToolbar } from "@/components/files/FilesToolbar";
import { FilesSelectionBar } from "@/components/files/FilesSelectionBar";
import { FilesListView } from "@/components/files/FilesListView";
import { FilesGridView } from "@/components/files/FilesGridView";
import {
  FilesDisabledState,
  FilesEmptyFolder,
  FilesEmptySearch,
  FilesErrorState,
  FilesLoadingState,
} from "@/components/files/FilesStates";
import {
  useFilesNavigation,
  readPreviewWidth,
  writePreviewWidth,
} from "@/components/files/useFilesNavigation";
import { useFilesSelection } from "@/components/files/useFilesSelection";
import {
  entryMatchesTypeFilter,
  sortEntries,
  type FilesEntry,
  type FilesRoot,
  type FilesSortKey,
  type FilesTypeFilter,
} from "@/components/files/types";
import { FilesPreviewPane } from "@/components/files/FilesPreviewPane";
import {
  CreateFolderDialog,
  MoveDialog,
  RenameDialog,
  UploadDialog,
} from "@/components/files/FilesMutationDialogs";
import {
  FilesMutationConfirmation,
  type FilesMutationPending,
} from "@/components/files/FilesMutationConfirmation";
import {
  FilesContextMenu,
  type FilesContextAction,
} from "@/components/files/FilesContextMenu";
import { FilesMobileActions } from "@/components/files/FilesMobileActions";
import {
  FilesCommandPalette,
  type FilesCommand,
} from "@/components/files/FilesCommandPalette";
import { FilesAssistantFab } from "@/components/files/FilesAssistantFab";
import {
  FilesAssistantPanel,
  type FilesAssistantFileCard,
} from "@/components/files/FilesAssistantPanel";
import { Button } from "@/components/ui/Button";

export default function FilesWorkspace() {
  const { toast } = useToast();
  const nav = useFilesNavigation();
  const selection = useFilesSelection();

  const [roots, setRoots] = useState<FilesRoot[]>([]);
  const [rootsLoaded, setRootsLoaded] = useState(false);
  const [enabled, setEnabled] = useState(true);
  const [entries, setEntries] = useState<FilesEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [focusedId, setFocusedId] = useState<string | null>(null);
  const [rootsDrawerOpen, setRootsDrawerOpen] = useState(false);
  const [mobilePreviewOpen, setMobilePreviewOpen] = useState(false);
  const [isNarrow, setIsNarrow] = useState(false);
  const [previewWidth, setPreviewWidth] = useState(360);
  const [createOpen, setCreateOpen] = useState(false);
  const [renameOpen, setRenameOpen] = useState(false);
  const [moveOpen, setMoveOpen] = useState(false);
  const [uploadOpen, setUploadOpen] = useState(false);
  const [pendingUploadFiles, setPendingUploadFiles] = useState<File[]>([]);
  const [uploadDestPath, setUploadDestPath] = useState("");
  const [externalDragOver, setExternalDragOver] = useState(false);
  const [pendingMutations, setPendingMutations] = useState<
    FilesMutationPending[]
  >([]);
  const [previewFileId, setPreviewFileId] = useState<string | null>(null);
  /** Aperçu immédiat depuis l'assistant (avant que le listing ait rechargé). */
  const [pendingAssistantPreview, setPendingAssistantPreview] = useState<{
    fileId: string;
    name: string;
  } | null>(null);
  /** Sélection après « Aller à la destination » (sans ouvrir l'aperçu). */
  const [pendingRevealFileId, setPendingRevealFileId] = useState<string | null>(
    null
  );
  const [typeFilter, setTypeFilter] = useState<FilesTypeFilter>("all");
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [totalListed, setTotalListed] = useState<number | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [contextMenu, setContextMenu] = useState<{
    entry: FilesEntry;
    x: number;
    y: number;
  } | null>(null);
  const [mobileActionsEntry, setMobileActionsEntry] =
    useState<FilesEntry | null>(null);
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [assistantOpen, setAssistantOpen] = useState(false);
  const [assistantSeed, setAssistantSeed] = useState<string | null>(null);
  const searchDebounce = useRef<number | null>(null);
  const loadGen = useRef(0);
  const navRef = useRef(nav);
  navRef.current = nav;

  useEffect(() => {
    setPreviewWidth(readPreviewWidth(360));
  }, []);

  useEffect(() => {
    const mq = window.matchMedia("(max-width: 1023px)");
    const sync = () => setIsNarrow(mq.matches);
    sync();
    mq.addEventListener("change", sync);
    return () => mq.removeEventListener("change", sync);
  }, []);

  const activeRoot = roots.find((r) => r.id === nav.rootId) ?? roots[0];
  const searching = Boolean(nav.q.trim());

  const sorted = useMemo(() => {
    const base = sortEntries(entries, nav.sort, nav.sortDir);
    if (typeFilter === "all") return base;
    return base.filter((e) => entryMatchesTypeFilter(e, typeFilter));
  }, [entries, nav.sort, nav.sortDir, typeFilter]);

  const orderedIds = useMemo(() => sorted.map((e) => e.fileId), [sorted]);

  const selectedEntries = useMemo(
    () => sorted.filter((e) => selection.selectedIds.has(e.fileId)),
    [sorted, selection.selectedIds]
  );

  const primarySelected =
    selectedEntries.find((e) => e.fileId === previewFileId) ??
    selectedEntries.find((e) => e.fileId === nav.selectedFileId) ??
    selectedEntries[0] ??
    sorted.find((e) => e.fileId === previewFileId) ??
    sorted.find((e) => e.fileId === nav.selectedFileId) ??
    null;

  // L’aperçu suit uniquement l’id explicite — pas le fallback sélection,
  // sinon « Fermer » ne peut pas cacher le panneau tant qu’un fichier reste sélectionné.
  const previewEntry =
    sorted.find(
      (e) => e.fileId === previewFileId && !e.isDirectory
    ) ??
    (nav.selectedFileId
      ? sorted.find(
          (e) => e.fileId === nav.selectedFileId && !e.isDirectory
        )
      : undefined) ??
    null;

  const previewTarget =
    previewEntry ??
    (pendingAssistantPreview &&
    (previewFileId === pendingAssistantPreview.fileId ||
      nav.selectedFileId === pendingAssistantPreview.fileId)
      ? {
          fileId: pendingAssistantPreview.fileId,
          name: pendingAssistantPreview.name,
        }
      : null);

  const closePreview = useCallback(() => {
    setPreviewFileId(null);
    setPendingAssistantPreview(null);
    nav.setSelectedFile(null);
    setMobilePreviewOpen(false);
  }, [nav]);

  useEffect(() => {
    if (nav.selectedFileId) setPreviewFileId(nav.selectedFileId);
  }, [nav.selectedFileId]);

  // Une fois le fichier dans le listing, on n'a plus besoin du fallback assistant.
  useEffect(() => {
    if (!pendingAssistantPreview || !previewEntry) return;
    if (previewEntry.fileId === pendingAssistantPreview.fileId) {
      setPendingAssistantPreview(null);
    }
  }, [previewEntry, pendingAssistantPreview]);

  // Restaure sélection / aperçu après list (URL `file=` ou F5).
  useEffect(() => {
    if (!nav.selectedFileId || entries.length === 0) return;
    const hit = entries.find((e) => e.fileId === nav.selectedFileId);
    if (!hit || hit.isDirectory) return;
    if (!selection.selectedIds.has(hit.fileId)) {
      selection.selectOnly(hit.fileId);
    }
    setPreviewFileId(hit.fileId);
    if (isNarrow) setMobilePreviewOpen(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- selectedIds Set identity; selectOnly is stable
  }, [entries, nav.selectedFileId, isNarrow, selection.selectedIds, selection.selectOnly]);

  // Après « Aller à la destination » : sélectionne le fichier sans ouvrir l'aperçu.
  useEffect(() => {
    if (!pendingRevealFileId || entries.length === 0) return;
    const hit = entries.find((e) => e.fileId === pendingRevealFileId);
    if (!hit || hit.isDirectory) return;
    selection.selectOnly(hit.fileId);
    setFocusedId(hit.fileId);
    setPreviewFileId(null);
    setMobilePreviewOpen(false);
    setPendingRevealFileId(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps -- selectOnly stable
  }, [entries, pendingRevealFileId, selection.selectOnly]);

  const loadRoots = useCallback(async () => {
    const { cachedGetJson } = await import("@/lib/client/fetch-cache");
    try {
      const res = await cachedGetJson<{
        enabled?: boolean;
        roots?: FilesRoot[];
        error?: string;
      }>("/api/files/roots", { ttlMs: 30_000 });
      const data = res.data ?? {};
      if (!res.ok) {
        setEnabled(false);
        setError(data.error ?? "Files indisponible");
        setRoots([]);
        return;
      }
      setEnabled(true);
      const list = (data.roots ?? []).filter((r) => r.enabled);
      setRoots(list);
      const { rootId, replaceParams } = navRef.current;
      if (!rootId && list[0]) {
        replaceParams({ root: list[0].id });
      }
    } finally {
      setRootsLoaded(true);
    }
  }, []);

  const loadListing = useCallback(
    async (opts?: { soft?: boolean }) => {
      const { rootId, path, q } = navRef.current;
      if (!rootId) return;
      const gen = ++loadGen.current;
      if (opts?.soft) setRefreshing(true);
      else setLoading(true);
      setError(null);
      try {
        const query = q.trim();
        if (query) {
          const sp = new URLSearchParams({
            q: query,
            root: rootId,
            mode: "all",
          });
          const res = await fetch(`/api/files/search?${sp}`);
          const data = (await res.json()) as {
            results?: FilesEntry[];
            error?: string;
            hint?: string;
          };
          if (gen !== loadGen.current) return;
          if (!res.ok) throw new Error(data.error ?? "Recherche échouée");
          const mapped = (data.results ?? []).map((r) => {
            const raw = r as FilesEntry & { filename?: string };
            return {
              ...raw,
              name: raw.name || raw.filename || "",
              isDirectory: Boolean(raw.isDirectory),
            };
          });
          setEntries(mapped);
          setNextCursor(null);
          setTotalListed(mapped.length);
        } else {
          const sp = new URLSearchParams({
            root: rootId,
            path,
            limit: "200",
          });
          const res = await fetch(`/api/files/list?${sp}`);
          const data = (await res.json()) as {
            entries?: FilesEntry[];
            nextCursor?: string | null;
            totalListed?: number;
            error?: string;
          };
          if (gen !== loadGen.current) return;
          if (!res.ok) throw new Error(data.error ?? "Liste échouée");
          setEntries(data.entries ?? []);
          setNextCursor(data.nextCursor ?? null);
          setTotalListed(data.totalListed ?? data.entries?.length ?? null);
        }
      } catch (err) {
        if (gen !== loadGen.current) return;
        setError(err instanceof Error ? err.message : "Erreur");
        setEntries([]);
        setNextCursor(null);
        setTotalListed(null);
      } finally {
        if (gen === loadGen.current) {
          setLoading(false);
          setRefreshing(false);
        }
      }
    },
    []
  );

  const loadMore = useCallback(async () => {
    const { rootId, path } = navRef.current;
    if (!rootId || !nextCursor || searching) return;
    setLoadingMore(true);
    try {
      const sp = new URLSearchParams({
        root: rootId,
        path,
        limit: "200",
        cursor: nextCursor,
      });
      const res = await fetch(`/api/files/list?${sp}`);
      const data = (await res.json()) as {
        entries?: FilesEntry[];
        nextCursor?: string | null;
        totalListed?: number;
        error?: string;
      };
      if (!res.ok) throw new Error(data.error ?? "Chargement échoué");
      setEntries((prev) => {
        const seen = new Set(prev.map((e) => e.fileId));
        const extra = (data.entries ?? []).filter((e) => !seen.has(e.fileId));
        return [...prev, ...extra];
      });
      setNextCursor(data.nextCursor ?? null);
      if (typeof data.totalListed === "number") setTotalListed(data.totalListed);
    } catch (err) {
      toast(err instanceof Error ? err.message : "Erreur", "error");
    } finally {
      setLoadingMore(false);
    }
  }, [nextCursor, searching, toast]);

  useEffect(() => {
    void loadRoots();
  }, [loadRoots]);

  useEffect(() => {
    if (!nav.rootId) return;
    void loadListing();
  }, [nav.rootId, nav.path, nav.q, loadListing]);

  useEffect(() => {
    if (nav.intent === "search" && nav.q) {
      nav.clearIntent();
    } else if (nav.intent === "list" || nav.intent === "browse") {
      nav.clearIntent();
    }
  }, [nav]);

  const onQueryChange = (value: string) => {
    if (searchDebounce.current) window.clearTimeout(searchDebounce.current);
    searchDebounce.current = window.setTimeout(() => {
      nav.setQuery(value);
    }, 280);
  };

  const handleOpen = (entry: FilesEntry) => {
    if (entry.isDirectory) {
      selection.clear();
      setPreviewFileId(null);
      setMobilePreviewOpen(false);
      nav.navigateToPath(entry.relativePath);
      return;
    }
    selection.selectOnly(entry.fileId);
    setPreviewFileId(entry.fileId);
    nav.setSelectedFile(entry.fileId);
    if (isNarrow) setMobilePreviewOpen(true);
  };

  const handleSelect = (
    entry: FilesEntry,
    opts: { additive: boolean; range: boolean }
  ) => {
    if (opts.range) {
      selection.selectRange(orderedIds, entry.fileId);
    } else if (opts.additive) {
      selection.toggle(entry.fileId);
    } else {
      selection.selectOnly(entry.fileId);
    }
    setFocusedId(entry.fileId);
    if (entry.isDirectory) {
      setPreviewFileId(null);
      nav.setSelectedFile(null);
      setMobilePreviewOpen(false);
      return;
    }
    setPreviewFileId(entry.fileId);
    nav.setSelectedFile(entry.fileId);
    if (isNarrow && !opts.additive && !opts.range) {
      setMobilePreviewOpen(true);
    }
  };

  const handleSortClick = (key: FilesSortKey) => {
    if (nav.sort === key) {
      nav.setSort(key, nav.sortDir === "asc" ? "desc" : "asc");
    } else {
      nav.setSort(key, key === "name" || key === "type" ? "asc" : "desc");
    }
  };

  const indexRoot = async () => {
    if (!nav.rootId) return;
    const res = await fetch("/api/files/index", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ rootId: nav.rootId }),
    });
    const data = (await res.json()) as {
      indexed?: number;
      skipped?: number;
      error?: string;
    };
    if (!res.ok) {
      toast(data.error ?? "Indexation échouée", "error");
      return;
    }
    toast(
      `Indexation : ${data.indexed ?? 0} indexés, ${data.skipped ?? 0} ignorés`,
      "success"
    );
    void loadListing({ soft: true });
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const target = e.target as HTMLElement | null;
      if (
        target &&
        (target.tagName === "INPUT" ||
          target.tagName === "TEXTAREA" ||
          target.isContentEditable)
      ) {
        return;
      }
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setPaletteOpen(true);
      }
      if (e.key === "/" && !e.ctrlKey && !e.metaKey) {
        e.preventDefault();
        const input = document.querySelector<HTMLInputElement>(
          'input[aria-label="Recherche fichiers"]'
        );
        input?.focus();
      }
      if (e.key === "F2" && selection.count === 1) {
        e.preventDefault();
        setRenameOpen(true);
      }
      if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === "n") {
        e.preventDefault();
        setCreateOpen(true);
      }
      if (e.key === "Backspace" && !nav.atRoot) {
        e.preventDefault();
        nav.goParent();
      }
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "a") {
        e.preventDefault();
        selection.selectAll(orderedIds);
      }
      if (e.key === "Escape") {
        selection.clear();
        setMobilePreviewOpen(false);
      }
      if (e.key === "Enter" && focusedId) {
        const entry = sorted.find((x) => x.fileId === focusedId);
        if (entry) handleOpen(entry);
      }
      if (e.key === "ArrowDown" || e.key === "ArrowUp") {
        e.preventDefault();
        if (orderedIds.length === 0) return;
        const idx = focusedId ? orderedIds.indexOf(focusedId) : -1;
        const next =
          e.key === "ArrowDown"
            ? orderedIds[Math.min(orderedIds.length - 1, idx + 1)]
            : orderedIds[Math.max(0, idx < 0 ? 0 : idx - 1)];
        if (next) {
          setFocusedId(next);
          const entry = sorted.find((x) => x.fileId === next);
          if (entry && !e.shiftKey) {
            selection.selectOnly(next);
            nav.setSelectedFile(next);
          } else if (entry && e.shiftKey) {
            selection.selectRange(orderedIds, next);
          }
        }
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const proposeMutations = async (bodies: Record<string, unknown>[]) => {
    if (bodies.length === 0) throw new Error("Aucune action à proposer");
    const results: FilesMutationPending[] = [];
    for (const body of bodies) {
      const res = await fetch("/api/files/propose", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = (await res.json()) as FilesMutationPending & {
        error?: string;
      };
      if (!res.ok) throw new Error(data.error ?? "Proposition échouée");
      results.push({
        actionId: data.actionId,
        confirmationToken: data.confirmationToken,
        expiresAt: data.expiresAt,
        op: data.op,
        payload: data.payload,
      });
    }
    setPendingMutations(results);
  };

  const proposeMutation = async (body: Record<string, unknown>) => {
    await proposeMutations([body]);
  };

  const openUploadForFiles = useCallback(
    (files: File[], destRelativePath?: string) => {
      const onlyFiles = files.filter((f) => f.size >= 0);
      if (onlyFiles.length === 0) return;
      setPendingUploadFiles(onlyFiles);
      setUploadDestPath(
        destRelativePath !== undefined ? destRelativePath : nav.path
      );
      setUploadOpen(true);
    },
    [nav.path]
  );

  const uploadFilesTo = async (
    destRootId: string,
    destRelativePath: string,
    files: File[]
  ) => {
    const form = new FormData();
    form.append("rootId", destRootId);
    form.append("destRelativePath", destRelativePath);
    for (const f of files) form.append("files", f, f.name);
    const res = await fetch("/api/files/upload", {
      method: "POST",
      body: form,
    });
    const data = (await res.json()) as {
      error?: string;
      uploaded?: unknown[];
    };
    if (!res.ok) throw new Error(data.error ?? "Échec de l'enregistrement");
    toast(
      `${data.uploaded?.length ?? files.length} fichier${
        (data.uploaded?.length ?? files.length) > 1 ? "s" : ""
      } enregistré${(data.uploaded?.length ?? files.length) > 1 ? "s" : ""}`,
      "success"
    );
    setPendingUploadFiles([]);
    void loadListing({ soft: true });
  };

  const handleContextAction = (action: FilesContextAction, entry: FilesEntry) => {
    selection.selectOnly(entry.fileId);
    setPreviewFileId(entry.fileId);
    nav.setSelectedFile(entry.fileId);
    switch (action) {
      case "open":
        handleOpen(entry);
        break;
      case "preview":
      case "info":
        if (window.matchMedia("(max-width: 1023px)").matches) {
          setMobilePreviewOpen(true);
        }
        break;
      case "analyze":
        setAssistantSeed(
          `Analyse le fichier « ${entry.name} » (fileId déjà sélectionné) et résume-le clairement.`
        );
        setAssistantOpen(true);
        break;
      case "rename":
        setRenameOpen(true);
        break;
      case "move":
        setMoveOpen(true);
        break;
    }
  };

  const handleDropOnFolder = async (
    folder: FilesEntry,
    draggedIds: string[]
  ) => {
    if (!nav.rootId || draggedIds.length === 0) return;
    const sources = draggedIds
      .map((id) => entries.find((e) => e.fileId === id))
      .filter((e): e is FilesEntry => Boolean(e));
    if (sources.length === 0) return;
    try {
      await proposeMutations(
        sources.map((source) => ({
          op: "move_file",
          sourceFileId: source.fileId,
          destRootId: nav.rootId,
          destRelativePath: `${folder.relativePath}/${source.name}`,
        }))
      );
    } catch (err) {
      toast(err instanceof Error ? err.message : "Déplacement impossible", "error");
    }
  };

  const handleCommand = (command: FilesCommand) => {
    switch (command) {
      case "search-focus": {
        const input = document.querySelector<HTMLInputElement>(
          'input[aria-label="Recherche fichiers"]'
        );
        input?.focus();
        break;
      }
      case "create-folder":
        setCreateOpen(true);
        break;
      case "go-documents": {
        const doc = roots.find((r) =>
          r.label.toLowerCase().includes("document")
        );
        if (doc) nav.setRoot(doc.id);
        break;
      }
      case "go-downloads": {
        const dl = roots.find((r) =>
          r.label.toLowerCase().includes("download")
        );
        if (dl) nav.setRoot(dl.id);
        break;
      }
      case "view-list":
        nav.setViewMode("list");
        break;
      case "view-grid":
        nav.setViewMode("grid");
        break;
      case "sort-name":
        nav.setSort("name", "asc");
        break;
      case "sort-mtime":
        nav.setSort("mtime", "desc");
        break;
      case "refresh":
        void loadListing({ soft: true });
        break;
      case "settings":
        window.location.href = "/settings/files";
        break;
    }
  };

  if (!enabled) return <FilesDisabledState />;

  const fileEntries = sorted.filter((e) => !e.isDirectory);
  const previewIndex = previewTarget
    ? fileEntries.findIndex((e) => e.fileId === previewTarget.fileId)
    : -1;
  const previewOpen = Boolean(previewTarget);

  const previewPanel = previewOpen && previewTarget ? (
    <FilesPreviewPane
      fileId={previewTarget.fileId}
      fileName={previewTarget.name}
      onClose={closePreview}
      onPrev={
        previewIndex > 0
          ? () => {
              const prev = fileEntries[previewIndex - 1]!;
              selection.selectOnly(prev.fileId);
              setPreviewFileId(prev.fileId);
              setPendingAssistantPreview(null);
              nav.setSelectedFile(prev.fileId);
            }
          : undefined
      }
      onNext={
        previewIndex >= 0 && previewIndex < fileEntries.length - 1
          ? () => {
              const next = fileEntries[previewIndex + 1]!;
              selection.selectOnly(next.fileId);
              setPreviewFileId(next.fileId);
              setPendingAssistantPreview(null);
              nav.setSelectedFile(next.fileId);
            }
          : undefined
      }
    />
  ) : null;

  return (
    <FilesLayout
      rootsNav={
        <FilesRootsNav
          roots={roots}
          activeRootId={activeRoot?.id ?? ""}
          loaded={rootsLoaded}
          onSelect={(id) => {
            selection.clear();
            setRootsDrawerOpen(false);
            nav.setRoot(id);
          }}
        />
      }
      toolbar={
        <FilesToolbar
          rootLabel={activeRoot?.label ?? "Files"}
          path={nav.path}
          atRoot={nav.atRoot}
          canGoBack={nav.canGoBack}
          canGoForward={nav.canGoForward}
          refreshing={refreshing}
          query={nav.q}
          viewMode={nav.viewMode}
          sort={nav.sort}
          sortDir={nav.sortDir}
          typeFilter={typeFilter}
          onBack={nav.goBack}
          onForward={nav.goForward}
          onParent={() => {
            selection.clear();
            nav.goParent();
          }}
          onRefresh={() => void loadListing({ soft: true })}
          onNavigateRoot={() => {
            selection.clear();
            nav.navigateToPath("");
          }}
          onNavigateSegment={(p) => {
            selection.clear();
            nav.navigateToPath(p);
          }}
          onQueryChange={onQueryChange}
          onSearchSubmit={() => void loadListing({ soft: true })}
          onViewModeChange={nav.setViewMode}
          onSortChange={nav.setSort}
          onTypeFilterChange={setTypeFilter}
          onCreateFolder={() => setCreateOpen(true)}
          onIndex={() => void indexRoot()}
        />
      }
      banner={null}
      overlay={
        <>
          <CreateFolderDialog
            open={createOpen}
            parentPath={nav.path}
            onClose={() => setCreateOpen(false)}
            onSubmit={async (name) => {
              if (!nav.rootId) throw new Error("Root manquante");
              const destRelativePath = nav.path
                ? `${nav.path}/${name}`
                : name;
              await proposeMutation({
                op: "create_directory",
                destRootId: nav.rootId,
                destRelativePath,
              });
            }}
          />
          <RenameDialog
            open={renameOpen}
            currentName={primarySelected?.name ?? ""}
            onClose={() => setRenameOpen(false)}
            onSubmit={async (newName) => {
              if (!primarySelected) throw new Error("Sélection manquante");
              await proposeMutation({
                op: "rename_file",
                sourceFileId: primarySelected.fileId,
                newName,
              });
            }}
          />
          <MoveDialog
            open={moveOpen}
            itemCount={Math.max(1, selection.count)}
            roots={roots.map((r) => ({ id: r.id, label: r.label }))}
            defaultRootId={nav.rootId}
            defaultPath={nav.path}
            onClose={() => setMoveOpen(false)}
            onSubmit={async (destRootId, destDir) => {
              const targets =
                selectedEntries.length > 0
                  ? selectedEntries
                  : primarySelected
                    ? [primarySelected]
                    : [];
              if (targets.length === 0) throw new Error("Aucune sélection");
              await proposeMutations(
                targets.map((t) => ({
                  op: "move_file",
                  sourceFileId: t.fileId,
                  destRootId,
                  destRelativePath: destDir
                    ? `${destDir}/${t.name}`
                    : t.name,
                }))
              );
            }}
          />
          <UploadDialog
            open={uploadOpen}
            files={pendingUploadFiles}
            roots={roots.map((r) => ({ id: r.id, label: r.label }))}
            defaultRootId={nav.rootId}
            defaultPath={uploadDestPath}
            onClose={() => {
              setUploadOpen(false);
              setPendingUploadFiles([]);
            }}
            onSubmit={uploadFilesTo}
          />
          {pendingMutations.length > 0 && (
            <div className="fixed bottom-4 left-1/2 z-50 w-[min(28rem,calc(100vw-1.5rem))] -translate-x-1/2">
              <FilesMutationConfirmation
                proposals={pendingMutations}
                onDone={() => {
                  setPendingMutations([]);
                  selection.clear();
                  void loadListing({ soft: true });
                }}
              />
            </div>
          )}
          <FilesContextMenu
            entry={contextMenu?.entry ?? null}
            x={contextMenu?.x ?? 0}
            y={contextMenu?.y ?? 0}
            onClose={() => setContextMenu(null)}
            onAction={handleContextAction}
          />
          <FilesMobileActions
            entry={mobileActionsEntry}
            onClose={() => setMobileActionsEntry(null)}
            onAction={handleContextAction}
          />
          <FilesCommandPalette
            open={paletteOpen}
            onClose={() => setPaletteOpen(false)}
            onCommand={handleCommand}
            rootLabels={{
              documents: roots.find((r) =>
                r.label.toLowerCase().includes("document")
              )?.label,
              downloads: roots.find((r) =>
                r.label.toLowerCase().includes("download")
              )?.label,
            }}
          />
          <FilesAssistantFab
            open={assistantOpen}
            onOpen={() => setAssistantOpen(true)}
            onClose={() => setAssistantOpen(false)}
          >
            {nav.rootId && activeRoot ? (
              <FilesAssistantPanel
                rootId={nav.rootId}
                rootLabel={activeRoot.label}
                currentPath={nav.path}
                selectedFileIds={[...selection.selectedIds]}
                seedMessage={assistantSeed}
                onSeedConsumed={() => setAssistantSeed(null)}
                onMutationDone={() => void loadListing({ soft: true })}
                onExternalFilesDrop={openUploadForFiles}
                onPreviewFile={(file: FilesAssistantFileCard) => {
                  // Aperçu seul — ne change pas le dossier courant.
                  setPendingRevealFileId(null);
                  selection.selectOnly(file.fileId);
                  setPreviewFileId(file.fileId);
                  setPendingAssistantPreview({
                    fileId: file.fileId,
                    name: file.name,
                  });
                  nav.replaceParams({ file: file.fileId });
                  setAssistantOpen(false);
                  if (isNarrow) setMobilePreviewOpen(true);
                }}
                onRevealFile={(file: FilesAssistantFileCard) => {
                  // Destination seule — pas d'aperçu.
                  setPreviewFileId(null);
                  setPendingAssistantPreview(null);
                  setMobilePreviewOpen(false);
                  if (file.isDirectory) {
                    selection.clear();
                    setPendingRevealFileId(null);
                    nav.pushParams({
                      ...(file.rootId !== nav.rootId
                        ? { root: file.rootId }
                        : {}),
                      path: file.relativePath || null,
                      file: null,
                      q: null,
                      intent: null,
                    });
                  } else {
                    const parent = file.relativePath.includes("/")
                      ? file.relativePath.slice(
                          0,
                          file.relativePath.lastIndexOf("/")
                        )
                      : "";
                    setPendingRevealFileId(file.fileId);
                    selection.selectOnly(file.fileId);
                    nav.pushParams({
                      ...(file.rootId !== nav.rootId
                        ? { root: file.rootId }
                        : {}),
                      path: parent || null,
                      file: null,
                      q: null,
                      intent: null,
                    });
                  }
                  setAssistantOpen(false);
                }}
              />
            ) : (
              <div className="p-4 text-sm text-muted">
                Aucune source Files active.
              </div>
            )}
          </FilesAssistantFab>
        </>
      }
      preview={previewPanel}
      previewOpen={Boolean(previewPanel) && !isNarrow}
      previewWidth={previewWidth}
      onPreviewWidthChange={(w) => {
        setPreviewWidth(w);
        writePreviewWidth(w);
      }}
      rootsDrawerOpen={rootsDrawerOpen}
      onToggleRootsDrawer={() => setRootsDrawerOpen((v) => !v)}
      onCloseRootsDrawer={() => setRootsDrawerOpen(false)}
      mobilePreviewFullscreen={
        Boolean(previewPanel) && isNarrow && mobilePreviewOpen
      }
      onCloseMobilePreview={closePreview}
    >
      <div
        className={
          externalDragOver
            ? "relative flex min-h-0 flex-1 flex-col ring-2 ring-inset ring-accent"
            : "relative flex min-h-0 flex-1 flex-col"
        }
        onDragEnter={(e) => {
          if (![...e.dataTransfer.types].includes("Files")) return;
          e.preventDefault();
          setExternalDragOver(true);
        }}
        onDragOver={(e) => {
          if (![...e.dataTransfer.types].includes("Files")) return;
          e.preventDefault();
          e.dataTransfer.dropEffect = "copy";
        }}
        onDragLeave={(e) => {
          if (e.currentTarget === e.target) setExternalDragOver(false);
        }}
        onDrop={(e) => {
          e.preventDefault();
          setExternalDragOver(false);
          const list = [...e.dataTransfer.files];
          if (list.length) openUploadForFiles(list);
        }}
      >
        {externalDragOver && (
          <div className="pointer-events-none absolute inset-0 z-20 flex items-center justify-center bg-accent/10 text-sm font-medium text-foreground">
            Déposer pour enregistrer dans ce dossier…
          </div>
        )}
      <FilesSelectionBar
        count={selection.count}
        onClear={selection.clear}
        onAnalyze={
          selection.count > 0
            ? () => {
                const names = selectedEntries.map((e) => e.name).join(", ");
                setAssistantSeed(
                  `Analyse ${
                    selection.count > 1
                      ? `ces ${selection.count} éléments (${names})`
                      : `le fichier « ${names} »`
                  } et résume ce qui est important.`
                );
                setAssistantOpen(true);
              }
            : undefined
        }
        onRename={
          selection.count === 1 && primarySelected
            ? () => setRenameOpen(true)
            : undefined
        }
        onMove={
          selection.count > 0 || primarySelected
            ? () => setMoveOpen(true)
            : undefined
        }
        onInfo={
          primarySelected
            ? () => {
                nav.setSelectedFile(primarySelected.fileId);
                if (window.matchMedia("(max-width: 1023px)").matches) {
                  setMobilePreviewOpen(true);
                }
              }
            : undefined
        }
      />

      {error && !loading ? (
        <FilesErrorState
          message={error}
          onRetry={() => void loadListing()}
        />
      ) : loading ? (
        <FilesLoadingState />
      ) : sorted.length === 0 ? (
        searching ? (
          <FilesEmptySearch onClear={() => nav.setQuery("")} />
        ) : (
          <FilesEmptyFolder />
        )
      ) : nav.viewMode === "grid" ? (
        <FilesGridView
          entries={sorted}
          selectedIds={selection.selectedIds}
          focusedId={focusedId}
          onFocus={setFocusedId}
          onOpen={handleOpen}
          onSelect={handleSelect}
          onContextMenu={(entry, x, y) => {
            if (window.matchMedia("(max-width: 1023px)").matches) {
              setMobileActionsEntry(entry);
            } else {
              setContextMenu({ entry, x, y });
            }
          }}
          onLongPressSelect={(entry) => {
            selection.toggle(entry.fileId);
            setPreviewFileId(entry.fileId);
            nav.setSelectedFile(entry.fileId);
            setMobileActionsEntry(entry);
          }}
          onDropOnFolder={(folder, ids) => {
            void handleDropOnFolder(folder, ids);
          }}
        />
      ) : (
        <FilesListView
          entries={sorted}
          selectedIds={selection.selectedIds}
          focusedId={focusedId}
          onFocus={setFocusedId}
          onOpen={handleOpen}
          onSelect={handleSelect}
          onContextMenu={(entry, x, y) => {
            if (window.matchMedia("(max-width: 1023px)").matches) {
              setMobileActionsEntry(entry);
            } else {
              setContextMenu({ entry, x, y });
            }
          }}
          onLongPressSelect={(entry) => {
            selection.toggle(entry.fileId);
            setPreviewFileId(entry.fileId);
            nav.setSelectedFile(entry.fileId);
            setMobileActionsEntry(entry);
          }}
          onDropOnFolder={(folder, ids) => {
            void handleDropOnFolder(folder, ids);
          }}
          sort={nav.sort}
          sortDir={nav.sortDir}
          onSort={handleSortClick}
        />
      )}

      {!loading && nextCursor && !searching && (
        <div className="shrink-0 border-t border-border-subtle px-4 py-2">
          <Button
            type="button"
            size="sm"
            variant="secondary"
            loading={loadingMore}
            onClick={() => void loadMore()}
          >
            Charger plus
            {totalListed != null ? ` (${entries.length}/${totalListed})` : ""}
          </Button>
        </div>
      )}

      {!loading && sorted.length > 0 && (
        <div className="shrink-0 border-t border-border-subtle px-4 py-1.5 text-xs text-muted">
          {sorted.length} élément{sorted.length > 1 ? "s" : ""}
          {typeFilter !== "all" && entries.length !== sorted.length
            ? ` filtrés / ${entries.length}`
            : totalListed != null && totalListed > entries.length
              ? ` sur ${totalListed}`
              : ""}
          {searching ? " · résultats de recherche" : ""}
          {" · Ctrl+K commandes"}
        </div>
      )}
      </div>
    </FilesLayout>
  );
}
