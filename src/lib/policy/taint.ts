export interface TaintState {
  untrustedDataRead: boolean;
  sources: string[];
}

export function createTaintState(): TaintState {
  return { untrustedDataRead: false, sources: [] };
}

export function markUntrustedRead(state: TaintState, source: string): TaintState {
  if (state.sources.includes(source)) {
    return state;
  }
  return {
    untrustedDataRead: true,
    sources: [...state.sources, source],
  };
}

export function applyTaintFromToolOutput(
  state: TaintState,
  toolName: string,
  taintPolicy: "none" | "output_untrusted"
): TaintState {
  if (taintPolicy !== "output_untrusted") {
    return state;
  }
  return markUntrustedRead(state, toolName);
}
