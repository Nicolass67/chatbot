export const runtime = "nodejs";

import {
  ensureModelManagerInitialized,
  getModelManager,
} from "@/lib/lm-studio/model-manager";
import { serializeModelRuntimeState } from "@/lib/runtime/model-state";
import { getSettings, updateSettings } from "@/lib/settings/service";

export async function POST(req: Request) {
  try {
    await ensureModelManagerInitialized();
    const body = (await req.json()) as { modelKey?: string };
    const modelKey = body.modelKey?.trim();
    if (!modelKey) {
      return Response.json({ error: "modelKey requis" }, { status: 400 });
    }

    const settings = await updateSettings({ selectedModel: modelKey });
    const mgr = getModelManager();
    mgr.setPreferredModel(modelKey, settings.contextLength);

    // Démarre le switch async ; la réponse 202 ne doit jamais prétendre "ready"
    // pour un modèle pas encore confirmé chargé.
    void mgr.scheduleSwitch(modelKey, settings.contextLength).catch(() => undefined);

    const snapshot = serializeModelRuntimeState(mgr.getState());
    const alreadyReady =
      snapshot.phase === "ready" && snapshot.loadedModel === modelKey;

    return Response.json(
      {
        ...(alreadyReady
          ? snapshot
          : {
              ...snapshot,
              phase: "loading" as const,
              targetModel: modelKey,
              preferredModel: modelKey,
              message:
                snapshot.message ??
                `Chargement de ${modelKey.split("/").pop() ?? modelKey}…`,
              error: undefined,
              progress: undefined,
            }),
        accepted: true,
      },
      { status: 202 }
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Erreur modèle";
    return Response.json({ error: message }, { status: 500 });
  }
}

export async function GET() {
  try {
    await ensureModelManagerInitialized();
    const settings = await getSettings();
    const mgr = getModelManager();
    const state = mgr.getState();
    return Response.json({
      ...serializeModelRuntimeState(state),
      preferredModel: settings.selectedModel || state.preferredModel,
    });
  } catch (error) {
    return Response.json(
      {
        error: error instanceof Error ? error.message : "Erreur modèle",
      },
      { status: 500 }
    );
  }
}
