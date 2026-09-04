"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import type {
  FilesSearchMode,
  FilesSortDir,
  FilesSortKey,
  FilesViewMode,
} from "./types";

const VIEW_KEY = "files.viewMode";
const PREVIEW_WIDTH_KEY = "files.previewWidth";

function parseView(v: string | null): FilesViewMode {
  return v === "grid" ? "grid" : "list";
}

function parseSort(v: string | null): FilesSortKey {
  if (v === "mtime" || v === "size" || v === "type") return v;
  return "name";
}

function parseDir(v: string | null): FilesSortDir {
  return v === "desc" ? "desc" : "asc";
}

function parseSearchMode(v: string | null): FilesSearchMode {
  // UI mode tabs retirés : recherche unifiée nom + contenu.
  if (v === "name" || v === "content") return v;
  return "all";
}

export function useFilesNavigation(initialRootId = "") {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const rootId = searchParams.get("root") ?? initialRootId;
  const path = searchParams.get("path") ?? "";
  const q = searchParams.get("q") ?? "";
  const searchMode = parseSearchMode(searchParams.get("searchMode"));
  const sort = parseSort(searchParams.get("sort"));
  const sortDir = parseDir(searchParams.get("dir"));
  const selectedFileId = searchParams.get("file");
  const intent = searchParams.get("intent");

  const [viewMode, setViewModeState] = useState<FilesViewMode>(() =>
    parseView(searchParams.get("view"))
  );

  useEffect(() => {
    const fromUrl = searchParams.get("view");
    if (fromUrl === "list" || fromUrl === "grid") {
      setViewModeState(fromUrl);
      return;
    }
    try {
      const stored = localStorage.getItem(VIEW_KEY);
      if (stored === "grid" || stored === "list") {
        setViewModeState(stored);
      }
    } catch {
      /* ignore */
    }
  }, [searchParams]);

  const [canGoBack, setCanGoBack] = useState(false);
  const [canGoForward, setCanGoForward] = useState(false);
  const historyDepth = useRef(0);

  const buildQuery = useCallback(
    (patch: Record<string, string | null | undefined>) => {
      const next = new URLSearchParams(searchParams.toString());
      for (const [key, value] of Object.entries(patch)) {
        if (value === null || value === undefined || value === "") {
          next.delete(key);
        } else {
          next.set(key, value);
        }
      }
      const qs = next.toString();
      return qs ? `${pathname}?${qs}` : pathname;
    },
    [pathname, searchParams]
  );

  const replaceParams = useCallback(
    (patch: Record<string, string | null | undefined>) => {
      router.replace(buildQuery(patch), { scroll: false });
    },
    [buildQuery, router]
  );

  const pushParams = useCallback(
    (patch: Record<string, string | null | undefined>) => {
      historyDepth.current += 1;
      setCanGoBack(true);
      setCanGoForward(false);
      router.push(buildQuery(patch), { scroll: false });
    },
    [buildQuery, router]
  );

  const setRoot = useCallback(
    (nextRootId: string) => {
      pushParams({
        root: nextRootId,
        path: null,
        file: null,
        q: null,
        intent: null,
      });
    },
    [pushParams]
  );

  const navigateToPath = useCallback(
    (nextPath: string, options?: { replace?: boolean }) => {
      const patch = {
        path: nextPath || null,
        file: null,
        q: null,
        intent: null,
      };
      if (options?.replace) replaceParams(patch);
      else pushParams(patch);
    },
    [pushParams, replaceParams]
  );

  const goParent = useCallback(() => {
    const parts = path.split("/").filter(Boolean);
    if (parts.length === 0) return;
    navigateToPath(parts.slice(0, -1).join("/"));
  }, [navigateToPath, path]);

  const goBack = useCallback(() => {
    if (typeof window === "undefined") return;
    historyDepth.current = Math.max(0, historyDepth.current - 1);
    setCanGoForward(true);
    setCanGoBack(historyDepth.current > 0 || window.history.length > 1);
    router.back();
  }, [router]);

  const goForward = useCallback(() => {
    if (typeof window === "undefined") return;
    historyDepth.current += 1;
    setCanGoBack(true);
    router.forward();
  }, [router]);

  const setQuery = useCallback(
    (nextQ: string, mode?: FilesSearchMode) => {
      replaceParams({
        q: nextQ || null,
        searchMode: mode ?? searchMode,
        file: null,
        intent: null,
      });
    },
    [replaceParams, searchMode]
  );

  const setSearchMode = useCallback(
    (mode: FilesSearchMode) => {
      replaceParams({ searchMode: mode === "name" ? null : mode });
    },
    [replaceParams]
  );

  const setSort = useCallback(
    (key: FilesSortKey, dir?: FilesSortDir) => {
      replaceParams({
        sort: key === "name" ? null : key,
        dir: (dir ?? sortDir) === "asc" ? null : dir ?? sortDir,
      });
    },
    [replaceParams, sortDir]
  );

  const setViewMode = useCallback(
    (mode: FilesViewMode) => {
      setViewModeState(mode);
      try {
        localStorage.setItem(VIEW_KEY, mode);
      } catch {
        /* ignore */
      }
      replaceParams({ view: mode === "list" ? null : mode });
    },
    [replaceParams]
  );

  const setSelectedFile = useCallback(
    (fileId: string | null) => {
      replaceParams({ file: fileId });
    },
    [replaceParams]
  );

  const clearIntent = useCallback(() => {
    replaceParams({ intent: null });
  }, [replaceParams]);

  useEffect(() => {
    setCanGoBack(typeof window !== "undefined" && window.history.length > 1);
    const onPop = () => {
      setCanGoBack(true);
      setCanGoForward(true);
    };
    window.addEventListener("popstate", onPop);
    return () => window.removeEventListener("popstate", onPop);
  }, []);

  const atRoot = !path;

  return useMemo(
    () => ({
      rootId,
      path,
      q,
      searchMode,
      sort,
      sortDir,
      viewMode,
      selectedFileId,
      intent,
      atRoot,
      canGoBack,
      canGoForward,
      setRoot,
      navigateToPath,
      goParent,
      goBack,
      goForward,
      setQuery,
      setSearchMode,
      setSort,
      setViewMode,
      setSelectedFile,
      clearIntent,
      replaceParams,
      pushParams,
    }),
    [
      rootId,
      path,
      q,
      searchMode,
      sort,
      sortDir,
      viewMode,
      selectedFileId,
      intent,
      atRoot,
      canGoBack,
      canGoForward,
      setRoot,
      navigateToPath,
      goParent,
      goBack,
      goForward,
      setQuery,
      setSearchMode,
      setSort,
      setViewMode,
      setSelectedFile,
      clearIntent,
      replaceParams,
      pushParams,
    ]
  );
}

export function readPreviewWidth(defaultWidth = 360): number {
  if (typeof window === "undefined") return defaultWidth;
  try {
    const raw = localStorage.getItem(PREVIEW_WIDTH_KEY);
    const n = raw ? Number(raw) : defaultWidth;
    if (!Number.isFinite(n)) return defaultWidth;
    return Math.min(640, Math.max(280, n));
  } catch {
    return defaultWidth;
  }
}

export function writePreviewWidth(width: number) {
  try {
    localStorage.setItem(PREVIEW_WIDTH_KEY, String(width));
  } catch {
    /* ignore */
  }
}
