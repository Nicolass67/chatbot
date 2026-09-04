"use client";

import { useCallback, useSyncExternalStore } from "react";

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n));
}

/** Cache mémoire : évite le flash defaultWidth→localStorage au remount. */
const memoryCache = new Map<string, number>();

function readWidth(
  storageKey: string,
  min: number,
  max: number,
  defaultWidth: number
): number {
  const mem = memoryCache.get(storageKey);
  if (mem != null) return clamp(mem, min, max);
  if (typeof window === "undefined") return defaultWidth;
  try {
    const raw = localStorage.getItem(storageKey);
    if (raw != null) {
      const n = Number(raw);
      if (Number.isFinite(n)) {
        const clamped = clamp(n, min, max);
        memoryCache.set(storageKey, clamped);
        return clamped;
      }
    }
  } catch {
    /* ignore */
  }
  return defaultWidth;
}

function subscribe(storageKey: string, onChange: () => void) {
  const onStorage = (e: StorageEvent) => {
    if (e.key === storageKey) onChange();
  };
  const eventName = `resize-width:${storageKey}`;
  window.addEventListener("storage", onStorage);
  window.addEventListener(eventName, onChange);
  return () => {
    window.removeEventListener("storage", onStorage);
    window.removeEventListener(eventName, onChange);
  };
}

/**
 * Largeur de panneau persistée (localStorage), pour side panels redimensionnables.
 * Lecture synchrone via cache mémoire + localStorage pour éviter les sauts au remount.
 */
export function useResizableWidth(options: {
  storageKey: string;
  defaultWidth: number;
  min: number;
  max: number;
}) {
  const { storageKey, defaultWidth, min, max } = options;

  const width = useSyncExternalStore(
    (onChange) => subscribe(storageKey, onChange),
    () => readWidth(storageKey, min, max, defaultWidth),
    () => defaultWidth
  );

  const setWidth = useCallback(
    (next: number | ((prev: number) => number)) => {
      const prev = readWidth(storageKey, min, max, defaultWidth);
      const value = typeof next === "function" ? next(prev) : next;
      const clamped = clamp(value, min, max);
      memoryCache.set(storageKey, clamped);
      try {
        localStorage.setItem(storageKey, String(clamped));
      } catch {
        /* ignore */
      }
      window.dispatchEvent(new Event(`resize-width:${storageKey}`));
    },
    [storageKey, min, max, defaultWidth]
  );

  return { width, setWidth, ready: true, min, max };
}
