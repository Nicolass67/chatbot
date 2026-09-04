export const runtime = "nodejs";

import { lmStudioHealthCheck } from "@/lib/lm-studio/client";
import {
  ensureModelManagerInitialized,
  getModelManager,
} from "@/lib/lm-studio/model-manager";
import { getSqlite } from "@/lib/db";
import { serializeModelRuntimeState } from "@/lib/runtime/model-state";

function checkSqlite(): { ok: boolean; message?: string } {
  try {
    getSqlite().prepare("SELECT 1 AS ok").get();
    return { ok: true };
  } catch (error) {
    return {
      ok: false,
      message: error instanceof Error ? error.message : String(error),
    };
  }
}

export async function GET() {
  const sqlite = checkSqlite();
  let lmStudioConnected = false;
  let modelState = serializeModelRuntimeState({
    phase: "idle",
    preferredModel: null,
    loadedModel: null,
    targetModel: null,
    pendingRequestCount: 0,
  });

  try {
    await ensureModelManagerInitialized();
    lmStudioConnected = await lmStudioHealthCheck();
    modelState = serializeModelRuntimeState(getModelManager().getState());
  } catch (error) {
    return Response.json(
      {
        status: "error",
        checks: {
          nextjs: { status: "ok" as const },
          sqlite: {
            status: sqlite.ok ? ("ok" as const) : ("error" as const),
            message: sqlite.message,
          },
          lmStudio: { status: "unavailable" as const },
          model: modelState,
        },
        message: error instanceof Error ? error.message : String(error),
        timestamp: new Date().toISOString(),
      },
      { status: 503 }
    );
  }

  const allOk = sqlite.ok && lmStudioConnected;
  const modelLoaded =
    modelState.phase === "ready" && !!modelState.currentModel;

  return Response.json(
    {
      status: allOk ? "ok" : "degraded",
      checks: {
        nextjs: { status: "ok" as const },
        sqlite: {
          status: sqlite.ok ? ("ok" as const) : ("error" as const),
          message: sqlite.message,
        },
        lmStudio: {
          status: lmStudioConnected
            ? ("connected" as const)
            : ("unavailable" as const),
        },
        model: {
          ...modelState,
          loaded: modelLoaded,
        },
      },
      timestamp: new Date().toISOString(),
    },
    { status: allOk ? 200 : 503 }
  );
}
