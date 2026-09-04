"use client";

import { useEffect, useState } from "react";
import {
  ArrowLeft,
  ArrowUp,
  ArrowUpDown,
  Check,
  FolderPlus,
  LayoutGrid,
  List,
  MoreHorizontal,
  RefreshCw,
  Search,
  X,
} from "lucide-react";
import { Dropdown } from "@/components/ui/Dropdown";
import { IconButton } from "@/components/ui/IconButton";
import {
  MobileBottomSheet,
  MobileSheetAction,
} from "@/components/ui/MobileBottomSheet";
import { cn } from "@/lib/utils/cn";
import { FilesNavControls, FilesBreadcrumbs } from "./FilesNavControls";
import type {
  FilesSortDir,
  FilesSortKey,
  FilesTypeFilter,
  FilesViewMode,
} from "./types";

interface FilesToolbarProps {
  rootLabel: string;
  path: string;
  atRoot: boolean;
  canGoBack: boolean;
  canGoForward: boolean;
  refreshing?: boolean;
  query: string;
  viewMode: FilesViewMode;
  sort: FilesSortKey;
  sortDir: FilesSortDir;
  typeFilter: FilesTypeFilter;
  onBack: () => void;
  onForward: () => void;
  onParent: () => void;
  onRefresh: () => void;
  onNavigateRoot: () => void;
  onNavigateSegment: (path: string) => void;
  onQueryChange: (q: string) => void;
  onSearchSubmit: () => void;
  onViewModeChange: (mode: FilesViewMode) => void;
  onSortChange: (key: FilesSortKey, dir: FilesSortDir) => void;
  onTypeFilterChange: (filter: FilesTypeFilter) => void;
  onCreateFolder?: () => void;
  onIndex?: () => void;
}

const TYPE_FILTERS: Array<{ id: FilesTypeFilter; label: string }> = [
  { id: "all", label: "Tout" },
  { id: "folders", label: "Dossiers" },
  { id: "images", label: "Images" },
  { id: "pdf", label: "PDF" },
  { id: "documents", label: "Docs" },
  { id: "indexed", label: "Indexés" },
];

const SORT_OPTIONS: Array<{
  value: `${FilesSortKey}:${FilesSortDir}`;
  label: string;
}> = [
  { value: "name:asc", label: "Nom A → Z" },
  { value: "name:desc", label: "Nom Z → A" },
  { value: "mtime:desc", label: "Plus récents" },
  { value: "mtime:asc", label: "Plus anciens" },
  { value: "size:desc", label: "Taille décroissante" },
  { value: "size:asc", label: "Taille croissante" },
  { value: "type:asc", label: "Type" },
];

export function FilesToolbar({
  rootLabel,
  path,
  atRoot,
  canGoBack,
  canGoForward,
  refreshing,
  query,
  viewMode,
  sort,
  sortDir,
  typeFilter,
  onBack,
  onForward,
  onParent,
  onRefresh,
  onNavigateRoot,
  onNavigateSegment,
  onQueryChange,
  onSearchSubmit,
  onViewModeChange,
  onSortChange,
  onTypeFilterChange,
  onCreateFolder,
  onIndex,
}: FilesToolbarProps) {
  const [draft, setDraft] = useState(query);
  const [searchOpen, setSearchOpen] = useState(Boolean(query));
  const [optionsOpen, setOptionsOpen] = useState(false);
  useEffect(() => setDraft(query), [query]);
  useEffect(() => {
    if (query) setSearchOpen(true);
  }, [query]);

  const sortValue = `${sort}:${sortDir}` as `${FilesSortKey}:${FilesSortDir}`;
  const activeFilterLabel =
    TYPE_FILTERS.find((f) => f.id === typeFilter)?.label ?? "Tout";

  const viewToggle = (
    <div className="flex shrink-0 items-center gap-0.5">
      <IconButton
        label="Vue liste"
        size="sm"
        variant={viewMode === "list" ? "subtle" : "ghost"}
        onClick={() => onViewModeChange("list")}
      >
        <List className="h-4 w-4" />
      </IconButton>
      <IconButton
        label="Vue grille"
        size="sm"
        variant={viewMode === "grid" ? "subtle" : "ghost"}
        onClick={() => onViewModeChange("grid")}
      >
        <LayoutGrid className="h-4 w-4" />
      </IconButton>
    </div>
  );

  const sortSelect = (
    <Dropdown
      label="Trier par"
      value={sortValue}
      options={SORT_OPTIONS}
      onChange={(value) => {
        const [k, d] = value.split(":") as [FilesSortKey, FilesSortDir];
        onSortChange(k, d);
      }}
      icon={<ArrowUpDown className="h-3.5 w-3.5 shrink-0 text-muted" />}
      placement="bottom"
      align="end"
      triggerClassName="h-9 max-w-[11rem] border border-border-subtle bg-surface px-2.5 text-sm text-foreground hover:bg-surface-hover"
      menuClassName="min-w-[13rem]"
      className="shrink-0"
    />
  );

  const searchField = (
    <div className="relative">
      <Search className="pointer-events-none absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
      <input
        value={draft}
        onChange={(e) => {
          setDraft(e.target.value);
          onQueryChange(e.target.value);
        }}
        onKeyDown={(e) => {
          if (e.key === "Enter") onSearchSubmit();
        }}
        placeholder="Rechercher un fichier…"
        className="h-9 w-full rounded-[var(--radius-md)] border border-border-subtle bg-transparent py-1.5 pl-9 pr-9 text-sm outline-none placeholder:text-muted-foreground focus:border-border-strong lg:h-8"
        aria-label="Recherche fichiers"
      />
      {draft && (
        <button
          type="button"
          className="absolute right-1.5 top-1/2 -translate-y-1/2 rounded p-1.5 text-muted hover:text-foreground"
          aria-label="Effacer la recherche"
          onClick={() => {
            setDraft("");
            onQueryChange("");
          }}
        >
          <X className="h-3.5 w-3.5" />
        </button>
      )}
    </div>
  );

  return (
    <div className="relative px-3 py-2 lg:space-y-2 lg:px-4 lg:py-2.5">
      {/* Mobile: 1 rangée (+ search optionnelle) */}
      <div className="lg:hidden">
        <div className="flex min-w-0 items-center gap-0.5">
          <button
            type="button"
            disabled={!canGoBack}
            onClick={onBack}
            className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-[var(--radius-md)] text-muted hover:bg-surface-hover hover:text-foreground disabled:opacity-40"
            aria-label="Précédent"
          >
            <ArrowLeft className="h-4 w-4" />
          </button>
          <button
            type="button"
            disabled={atRoot}
            onClick={onParent}
            className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-[var(--radius-md)] text-muted hover:bg-surface-hover hover:text-foreground disabled:opacity-40"
            aria-label="Dossier parent"
          >
            <ArrowUp className="h-4 w-4" />
          </button>
          <FilesBreadcrumbs
            rootLabel={rootLabel}
            path={path}
            onNavigateRoot={onNavigateRoot}
            onNavigateSegment={onNavigateSegment}
          />
          <button
            type="button"
            className={cn(
              "inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-[var(--radius-md)]",
              "text-muted hover:bg-surface-hover hover:text-foreground",
              searchOpen && "bg-surface-hover text-foreground"
            )}
            aria-label="Rechercher"
            aria-pressed={searchOpen}
            onClick={() => setSearchOpen((o) => !o)}
          >
            <Search className="h-4 w-4" />
          </button>
          <button
            type="button"
            className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-[var(--radius-md)] text-muted hover:bg-surface-hover hover:text-foreground"
            aria-label="Options fichiers"
            onClick={() => setOptionsOpen(true)}
          >
            <MoreHorizontal className="h-4 w-4" />
          </button>
        </div>
        {searchOpen && <div className="mt-2">{searchField}</div>}
        {typeFilter !== "all" && !searchOpen && (
          <p className="mt-1.5 truncate text-[11px] text-muted">
            Filtre : {activeFilterLabel}
          </p>
        )}
      </div>

      {/* Desktop: 3 rangées */}
      <div className="hidden space-y-2 lg:block">
        <div className="flex min-w-0 items-center gap-1.5">
          <FilesNavControls
            canGoBack={canGoBack}
            canGoForward={canGoForward}
            atRoot={atRoot}
            refreshing={refreshing}
            onBack={onBack}
            onForward={onForward}
            onParent={onParent}
            onRefresh={onRefresh}
          />
          <FilesBreadcrumbs
            rootLabel={rootLabel}
            path={path}
            onNavigateRoot={onNavigateRoot}
            onNavigateSegment={onNavigateSegment}
          />
          <div className="ml-auto">{viewToggle}</div>
        </div>

        {searchField}

        <div className="flex min-w-0 items-center gap-2">
          <div
            className="-mx-1 flex min-w-0 flex-1 gap-1.5 overflow-x-auto px-1 pb-0.5 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
            role="group"
            aria-label="Filtrer par type"
          >
            {TYPE_FILTERS.map((f) => (
              <button
                key={f.id}
                type="button"
                onClick={() => onTypeFilterChange(f.id)}
                className={cn(
                  "shrink-0 rounded-[var(--radius-sm)] px-2 py-1 text-[12px] transition-colors",
                  typeFilter === f.id
                    ? "bg-accent-subtle font-medium text-accent"
                    : "text-muted hover:bg-surface-hover hover:text-foreground"
                )}
              >
                {f.label}
              </button>
            ))}
          </div>

          {sortSelect}

          {onCreateFolder && (
            <IconButton
              label="Nouveau dossier"
              size="sm"
              variant="subtle"
              onClick={onCreateFolder}
            >
              <FolderPlus className="h-4 w-4" />
            </IconButton>
          )}
          {onIndex && (
            <IconButton
              label="Indexer cette source"
              size="sm"
              variant="ghost"
              className="hidden sm:inline-flex"
              onClick={onIndex}
            >
              <RefreshCw className="h-4 w-4" />
            </IconButton>
          )}
        </div>
      </div>

      <MobileBottomSheet
        open={optionsOpen}
        onClose={() => setOptionsOpen(false)}
        title="Options"
        description="Vue, filtres et actions"
      >
        <div className="space-y-4 p-2">
          <section className="space-y-2">
            <p className="px-1 text-[10px] font-medium uppercase tracking-[0.06em] text-muted-foreground">
              Vue
            </p>
            <div className="flex gap-2 px-1">
              <button
                type="button"
                onClick={() => onViewModeChange("list")}
                className={cn(
                  "flex min-h-10 flex-1 items-center justify-center gap-2 rounded-[var(--radius-md)] text-sm",
                  viewMode === "list"
                    ? "bg-accent-subtle font-medium text-accent"
                    : "bg-surface-hover text-muted"
                )}
              >
                <List className="h-4 w-4" />
                Liste
              </button>
              <button
                type="button"
                onClick={() => onViewModeChange("grid")}
                className={cn(
                  "flex min-h-10 flex-1 items-center justify-center gap-2 rounded-[var(--radius-md)] text-sm",
                  viewMode === "grid"
                    ? "bg-accent-subtle font-medium text-accent"
                    : "bg-surface-hover text-muted"
                )}
              >
                <LayoutGrid className="h-4 w-4" />
                Grille
              </button>
            </div>
          </section>

          <section className="space-y-2">
            <p className="px-1 text-[10px] font-medium uppercase tracking-[0.06em] text-muted-foreground">
              Filtrer
            </p>
            <div className="flex flex-wrap gap-1.5 px-1">
              {TYPE_FILTERS.map((f) => (
                <button
                  key={f.id}
                  type="button"
                  onClick={() => onTypeFilterChange(f.id)}
                  className={cn(
                    "rounded-[var(--radius-sm)] px-2.5 py-1.5 text-[12px] transition-colors",
                    typeFilter === f.id
                      ? "bg-accent-subtle font-medium text-accent"
                      : "bg-surface-hover text-muted"
                  )}
                >
                  {f.label}
                </button>
              ))}
            </div>
          </section>

          <section className="space-y-1">
            <p className="px-1 text-[10px] font-medium uppercase tracking-[0.06em] text-muted-foreground">
              Trier
            </p>
            <ul className="space-y-0.5">
              {SORT_OPTIONS.map((opt) => (
                <li key={opt.value}>
                  <button
                    type="button"
                    onClick={() => {
                      const [k, d] = opt.value.split(":") as [
                        FilesSortKey,
                        FilesSortDir,
                      ];
                      onSortChange(k, d);
                    }}
                    className={cn(
                      "flex min-h-11 w-full items-center justify-between gap-2 rounded-[var(--radius-md)] px-3 py-2 text-left text-sm hover:bg-surface-hover",
                      sortValue === opt.value && "bg-surface-hover font-medium"
                    )}
                  >
                    {opt.label}
                    {sortValue === opt.value ? (
                      <Check className="h-4 w-4 text-accent" />
                    ) : null}
                  </button>
                </li>
              ))}
            </ul>
          </section>

          <section className="space-y-0.5 border-t border-border-subtle pt-2">
            <MobileSheetAction
              label="Actualiser"
              icon={
                <RefreshCw
                  className={cn("h-4 w-4", refreshing && "animate-spin")}
                />
              }
              onClick={() => {
                onRefresh();
                setOptionsOpen(false);
              }}
              disabled={refreshing}
            />
            {onCreateFolder && (
              <MobileSheetAction
                label="Nouveau dossier"
                icon={<FolderPlus className="h-4 w-4" />}
                onClick={() => {
                  onCreateFolder();
                  setOptionsOpen(false);
                }}
              />
            )}
            {onIndex && (
              <MobileSheetAction
                label="Indexer cette source"
                icon={<RefreshCw className="h-4 w-4" />}
                onClick={() => {
                  onIndex();
                  setOptionsOpen(false);
                }}
              />
            )}
          </section>
        </div>
      </MobileBottomSheet>
    </div>
  );
}
