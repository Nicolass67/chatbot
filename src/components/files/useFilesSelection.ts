"use client";

import { useCallback, useState } from "react";

export function useFilesSelection() {
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [anchorId, setAnchorId] = useState<string | null>(null);
  const [selectionMode, setSelectionMode] = useState(false);

  const clear = useCallback(() => {
    setSelectedIds(new Set());
    setAnchorId(null);
    setSelectionMode(false);
  }, []);

  const selectOnly = useCallback((id: string) => {
    setSelectedIds(new Set([id]));
    setAnchorId(id);
  }, []);

  const toggle = useCallback((id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
    setAnchorId(id);
    setSelectionMode(true);
  }, []);

  const selectRange = useCallback((orderedIds: string[], toId: string) => {
    setSelectedIds((prev) => {
      const from = anchorId && orderedIds.includes(anchorId) ? anchorId : toId;
      const a = orderedIds.indexOf(from);
      const b = orderedIds.indexOf(toId);
      if (a < 0 || b < 0) return new Set([toId]);
      const [lo, hi] = a < b ? [a, b] : [b, a];
      const next = new Set(prev);
      for (let i = lo; i <= hi; i += 1) next.add(orderedIds[i]!);
      return next;
    });
    setSelectionMode(true);
  }, [anchorId]);

  const selectAll = useCallback((ids: string[]) => {
    setSelectedIds(new Set(ids));
    setSelectionMode(true);
  }, []);

  return {
    selectedIds,
    selectionMode,
    setSelectionMode,
    clear,
    selectOnly,
    toggle,
    selectRange,
    selectAll,
    count: selectedIds.size,
    has: (id: string) => selectedIds.has(id),
  };
}
