import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/lm-studio/native-api", () => ({
  fetchNativeModels: vi.fn(),
  findModelDisplayName: vi.fn((_models: unknown[], key: string) => key),
  getLoadedLlmInstances: vi.fn(),
  loadNativeModel: vi.fn(),
  unloadNativeModel: vi.fn(),
  verifySingleLlmLoaded: vi.fn(),
  waitUntilInstanceUnloaded: vi.fn(),
}));

vi.mock("@/lib/settings/service", () => ({
  getSettings: vi.fn().mockResolvedValue({
    selectedModel: "model-a",
    contextLength: 8192,
  }),
}));

import {
  fetchNativeModels,
  getLoadedLlmInstances,
  loadNativeModel,
  unloadNativeModel,
  verifySingleLlmLoaded,
  waitUntilInstanceUnloaded,
} from "@/lib/lm-studio/native-api";
import {
  ModelManager,
  resetModelManager,
} from "@/lib/lm-studio/model-manager";

describe("ModelManager", () => {
  beforeEach(() => {
    resetModelManager();
    vi.clearAllMocks();
    vi.mocked(waitUntilInstanceUnloaded).mockResolvedValue(undefined);
    vi.mocked(verifySingleLlmLoaded).mockResolvedValue(true);
    vi.mocked(loadNativeModel).mockResolvedValue({ instanceId: "inst-b" });
    vi.mocked(unloadNativeModel).mockResolvedValue(undefined);
  });

  it("passe en ready si le modèle préféré est déjà chargé", async () => {
    vi.mocked(fetchNativeModels).mockResolvedValue([
      {
        type: "llm",
        key: "model-a",
        display_name: "Model A",
        loaded_instances: [{ id: "inst-a" }],
      },
    ]);
    vi.mocked(getLoadedLlmInstances).mockReturnValue([
      { modelKey: "model-a", instanceId: "inst-a", displayName: "Model A" },
    ]);

    const mgr = new ModelManager();
    const state = await mgr.syncWithLmStudio({ preferredModel: "model-a" });

    expect(state.phase).toBe("ready");
    expect(state.loadedModel).toBe("model-a");
    expect(loadNativeModel).not.toHaveBeenCalled();
    expect(unloadNativeModel).not.toHaveBeenCalled();
  });

  it("décharge puis charge lors d'un changement de modèle", async () => {
    vi.mocked(fetchNativeModels)
      .mockResolvedValueOnce([
        {
          type: "llm",
          key: "model-a",
          display_name: "Model A",
          loaded_instances: [{ id: "inst-a" }],
        },
      ])
      .mockResolvedValueOnce([
        {
          type: "llm",
          key: "model-a",
          display_name: "Model A",
          loaded_instances: [],
        },
        { type: "llm", key: "model-b", display_name: "Model B" },
      ])
      .mockResolvedValue([
        {
          type: "llm",
          key: "model-b",
          display_name: "Model B",
          loaded_instances: [{ id: "inst-b" }],
        },
      ]);

    vi.mocked(getLoadedLlmInstances)
      .mockReturnValueOnce([
        { modelKey: "model-a", instanceId: "inst-a", displayName: "Model A" },
      ])
      .mockReturnValueOnce([])
      .mockReturnValue([
        { modelKey: "model-b", instanceId: "inst-b", displayName: "Model B" },
      ]);

    const mgr = new ModelManager();
    await mgr.scheduleSwitch("model-b");

    expect(unloadNativeModel).toHaveBeenCalledWith("inst-a");
    expect(loadNativeModel).toHaveBeenCalledWith("model-b", {
      contextLength: 8192,
    });
    expect(mgr.getState().phase).toBe("ready");
    expect(mgr.getState().loadedModel).toBe("model-b");
  });

  it("coalesce les changements rapides vers le dernier modèle demandé", async () => {
    let loaded: Array<{
      modelKey: string;
      instanceId: string;
      displayName: string;
    }> = [];

    vi.mocked(fetchNativeModels).mockImplementation(async () => {
      const models = [];
      if (loaded.some((l) => l.modelKey === "model-a")) {
        models.push({
          type: "llm" as const,
          key: "model-a",
          display_name: "Model A",
          loaded_instances: [{ id: "inst-a" }],
        });
      }
      if (loaded.some((l) => l.modelKey === "model-b")) {
        models.push({
          type: "llm" as const,
          key: "model-b",
          display_name: "Model B",
          loaded_instances: [{ id: "inst-b" }],
        });
      }
      if (loaded.some((l) => l.modelKey === "model-c")) {
        models.push({
          type: "llm" as const,
          key: "model-c",
          display_name: "Model C",
          loaded_instances: [{ id: "inst-c" }],
        });
      }
      return models;
    });

    vi.mocked(getLoadedLlmInstances).mockImplementation(() => [...loaded]);

    vi.mocked(unloadNativeModel).mockImplementation(async (id) => {
      loaded = loaded.filter((l) => l.instanceId !== id);
    });

    vi.mocked(loadNativeModel).mockImplementation(async (key) => {
      loaded = loaded.filter((l) => l.modelKey !== key);
      const instanceId = `inst-${key.split("-")[1]}`;
      loaded.push({
        modelKey: key,
        instanceId,
        displayName: key,
      });
      return { instanceId };
    });

    loaded = [
      { modelKey: "model-a", instanceId: "inst-a", displayName: "Model A" },
    ];

    const mgr = new ModelManager();
    const p1 = mgr.scheduleSwitch("model-b");
    const p2 = mgr.scheduleSwitch("model-c");
    await Promise.all([p1, p2]);

    expect(mgr.getState().loadedModel).toBe("model-c");
    expect(loadNativeModel).toHaveBeenCalledWith("model-c", {
      contextLength: 8192,
    });
    expect(loadNativeModel).not.toHaveBeenCalledWith("model-b", expect.anything());
  });

  it("incrémente pendingRequestCount pendant ensureModelReady", async () => {
    vi.mocked(fetchNativeModels).mockResolvedValue([]);
    vi.mocked(getLoadedLlmInstances).mockReturnValue([]);

    let resolveLoad!: () => void;
    vi.mocked(loadNativeModel).mockImplementation(
      () =>
        new Promise((resolve) => {
          resolveLoad = () => resolve({ instanceId: "inst-a" });
        })
    );

    const mgr = new ModelManager();
    const readyPromise = mgr.ensureModelReady("model-a");

    await vi.waitFor(() => {
      expect(mgr.getState().pendingRequestCount).toBe(1);
      expect(loadNativeModel).toHaveBeenCalled();
    });

    resolveLoad!();
    await readyPromise;

    expect(mgr.getState().pendingRequestCount).toBe(0);
    expect(mgr.getState().phase).toBe("ready");
  });
});
