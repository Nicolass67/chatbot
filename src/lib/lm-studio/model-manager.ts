import {
  fetchNativeModels,
  findModelDisplayName,
  getLoadedLlmInstances,
  loadNativeModel,
  unloadNativeModel,
  verifySingleLlmLoaded,
  waitUntilInstanceUnloaded,
} from "@/lib/lm-studio/native-api";
import { getSettings } from "@/lib/settings/service";
import type {
  ModelLifecyclePhase,
  ModelLifecycleStep,
  ModelRuntimeSnapshot,
} from "@/lib/runtime/types";

export type { ModelLifecyclePhase, ModelLifecycleStep, ModelRuntimeSnapshot };

const INITIAL_STATE: ModelRuntimeSnapshot = {
  phase: "idle",
  preferredModel: null,
  loadedModel: null,
  targetModel: null,
  pendingRequestCount: 0,
};

type StateListener = (state: ModelRuntimeSnapshot) => void;

export class ModelManager {
  private state: ModelRuntimeSnapshot = { ...INITIAL_STATE };
  private desiredModel: string | null = null;
  private desiredContextLength = 8192;
  private switchChain: Promise<void> = Promise.resolve();
  private switchRunning = false;
  private readyWaiters: Array<{
    expectedModel: string;
    resolve: () => void;
    reject: (err: Error) => void;
  }> = [];
  private listeners = new Set<StateListener>();

  getState(): ModelRuntimeSnapshot {
    return { ...this.state };
  }

  isSwitchRunning(): boolean {
    return this.switchRunning;
  }

  subscribe(listener: StateListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  setPreferredModel(modelKey: string | null, contextLength?: number): void {
    if (modelKey) this.desiredModel = modelKey;
    if (contextLength) this.desiredContextLength = contextLength;
    this.patchState({ preferredModel: modelKey ?? this.state.preferredModel });
  }

  private patchState(patch: Partial<ModelRuntimeSnapshot>): void {
    this.state = { ...this.state, ...patch };
    for (const listener of this.listeners) listener(this.getState());
  }

  private rejectWaiters(error: Error): void {
    const waiters = this.readyWaiters;
    this.readyWaiters = [];
    for (const w of waiters) w.reject(error);
  }

  private resolveWaitersForModel(modelKey: string): void {
    const matching = this.readyWaiters.filter(
      (w) => w.expectedModel === modelKey
    );
    this.readyWaiters = this.readyWaiters.filter(
      (w) => w.expectedModel !== modelKey
    );
    for (const w of matching) w.resolve();
  }

  async syncWithLmStudio(options?: {
    preferredModel?: string | null;
    contextLength?: number;
  }): Promise<ModelRuntimeSnapshot> {
    if (options?.preferredModel !== undefined) {
      this.desiredModel = options.preferredModel;
      this.patchState({ preferredModel: options.preferredModel });
    }
    if (options?.contextLength) {
      this.desiredContextLength = options.contextLength;
    }

    try {
      const models = await fetchNativeModels();
      const loaded = getLoadedLlmInstances(models);
      const preferred = this.desiredModel;

      if (loaded.length === 0) {
        if (preferred) {
          await this.scheduleSwitch(preferred);
          return this.getState();
        }
        this.patchState({
          phase: "idle",
          loadedModel: null,
          targetModel: null,
          step: undefined,
          message: undefined,
          error: undefined,
          progress: undefined,
        });
        return this.getState();
      }

      if (loaded.length === 1 && preferred && loaded[0].modelKey === preferred) {
        this.patchState({
          phase: "ready",
          loadedModel: loaded[0].modelKey,
          targetModel: null,
          step: undefined,
          message: undefined,
          error: undefined,
          progress: undefined,
        });
        this.resolveWaitersForModel(preferred);
        return this.getState();
      }

      if (preferred) {
        await this.scheduleSwitch(preferred);
        return this.getState();
      }

      this.patchState({
        phase: "ready",
        loadedModel: loaded[0]?.modelKey ?? null,
        message: "Modèle chargé différent de la préférence",
      });
      return this.getState();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.patchState({ phase: "error", error: message, message });
      this.rejectWaiters(error instanceof Error ? error : new Error(message));
      return this.getState();
    }
  }

  scheduleSwitch(modelKey: string, contextLength?: number): Promise<void> {
    this.desiredModel = modelKey;
    if (contextLength) this.desiredContextLength = contextLength;
    // Marquer loading immédiatement (évite un GET status encore "ready" pendant la file)
    const alreadyReady =
      this.state.phase === "ready" && this.state.loadedModel === modelKey;
    if (!alreadyReady) {
      this.patchState({
        preferredModel: modelKey,
        targetModel: modelKey,
        phase: "loading",
        message: `Chargement de ${modelKey.split("/").pop() ?? modelKey}…`,
        error: undefined,
        progress: undefined,
      });
    } else {
      this.patchState({ preferredModel: modelKey, targetModel: modelKey });
    }

    this.switchChain = this.switchChain
      .catch(() => undefined)
      .then(() => this.runSwitchCoalesced());
    return this.switchChain;
  }

  private async runSwitchCoalesced(): Promise<void> {
    this.switchRunning = true;
    try {
      while (this.desiredModel) {
        const target = this.desiredModel;
        const contextLength = this.desiredContextLength;
        await this.performSwitch(target, contextLength);
        if (this.desiredModel === target && this.state.phase === "ready") {
          break;
        }
      }
    } finally {
      this.switchRunning = false;
    }
  }

  private async performSwitch(
    targetModelKey: string,
    contextLength: number
  ): Promise<void> {
    this.patchState({
      phase: "loading",
      targetModel: targetModelKey,
      error: undefined,
      progress: undefined,
    });

    try {
      let models = await fetchNativeModels();
      let loaded = getLoadedLlmInstances(models);
      const targetLabel = findModelDisplayName(models, targetModelKey);

      const alreadyOnlyTarget =
        loaded.length === 1 && loaded[0].modelKey === targetModelKey;

      if (!alreadyOnlyTarget) {
        for (const inst of loaded) {
          if (this.desiredModel !== targetModelKey) return;
          this.patchState({
            phase: "unloading",
            step: "unloading",
            message: `Déchargement de ${inst.displayName}…`,
            progress: undefined,
          });
          await unloadNativeModel(inst.instanceId);
          await waitUntilInstanceUnloaded(inst.instanceId);
        }

        models = await fetchNativeModels();
        loaded = getLoadedLlmInstances(models);
      }

      const isTargetLoaded = loaded.some((i) => i.modelKey === targetModelKey);

      if (!isTargetLoaded) {
        if (this.desiredModel !== targetModelKey) return;
        this.patchState({
          phase: "loading",
          step: "loading",
          message: `Chargement de ${targetLabel}…`,
          progress: undefined,
        });
        await loadNativeModel(targetModelKey, { contextLength });
      }

      if (this.desiredModel !== targetModelKey) return;

      this.patchState({
        phase: "loading",
        step: "initializing",
        message: "Initialisation…",
        progress: undefined,
      });

      const ok = await verifySingleLlmLoaded(targetModelKey);
      if (!ok) {
        throw new Error(
          `Le modèle ${targetLabel} n'a pas été confirmé comme unique instance chargée.`
        );
      }

      this.patchState({
        phase: "ready",
        loadedModel: targetModelKey,
        targetModel: null,
        step: undefined,
        message: undefined,
        error: undefined,
        progress: undefined,
      });
      this.resolveWaitersForModel(targetModelKey);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.patchState({
        phase: "error",
        error: message,
        message,
        progress: undefined,
      });
      this.rejectWaiters(error instanceof Error ? error : new Error(message));
      throw error;
    }
  }

  async ensureModelReady(
    modelKey: string,
    contextLength?: number
  ): Promise<void> {
    this.desiredModel = modelKey;
    if (contextLength) this.desiredContextLength = contextLength;
    this.patchState({
      preferredModel: modelKey,
      pendingRequestCount: this.state.pendingRequestCount + 1,
    });

    try {
      const ready =
        this.state.phase === "ready" &&
        this.state.loadedModel === modelKey &&
        !this.switchRunning;

      if (ready) return;

      await this.scheduleSwitch(modelKey, contextLength);

      if (this.state.phase !== "ready" || this.state.loadedModel !== modelKey) {
        throw new Error(
          this.state.error ?? `Le modèle ${modelKey} n'est pas prêt.`
        );
      }
    } finally {
      this.patchState({
        pendingRequestCount: Math.max(0, this.state.pendingRequestCount - 1),
      });
    }
  }
}

let manager: ModelManager | null = null;
let initPromise: Promise<void> | null = null;

export function getModelManager(): ModelManager {
  if (!manager) manager = new ModelManager();
  return manager;
}

export function resetModelManager(): void {
  manager = null;
  initPromise = null;
}

export async function ensureModelManagerInitialized(): Promise<void> {
  if (!initPromise) {
    initPromise = (async () => {
      const settings = await getSettings();
      const mgr = getModelManager();
      mgr.setPreferredModel(
        settings.selectedModel || null,
        settings.contextLength
      );
      await mgr.syncWithLmStudio({
        preferredModel: settings.selectedModel || null,
        contextLength: settings.contextLength,
      });
    })();
  }
  await initPromise;
}
