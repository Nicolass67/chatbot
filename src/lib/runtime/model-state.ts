import type { ModelRuntimeSnapshot } from "./types";

/** Serialized model runtime state for API responses. */
export interface ModelRuntimeStateResponse {
  phase: ModelRuntimeSnapshot["phase"];
  currentModel: string | null;
  targetModel: string | null;
  preferredModel: string | null;
  step?: ModelRuntimeSnapshot["step"];
  message?: string;
  error?: string;
  progress?: number;
  pendingRequestCount: number;
  /** @deprecated Use currentModel */
  loadedModel: string | null;
}

export function serializeModelRuntimeState(
  state: ModelRuntimeSnapshot
): ModelRuntimeStateResponse {
  return {
    phase: state.phase,
    currentModel: state.loadedModel,
    targetModel: state.targetModel,
    preferredModel: state.preferredModel,
    step: state.step,
    message: state.message,
    error: state.error,
    progress: state.progress,
    pendingRequestCount: state.pendingRequestCount,
    loadedModel: state.loadedModel,
  };
}
