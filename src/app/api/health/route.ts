export const runtime = "nodejs";

import { lmStudioHealthCheck } from "@/lib/lm-studio/client";
import {
  ensureModelManagerInitialized,
  getModelManager,
} from "@/lib/lm-studio/model-manager";
import { getSqlite } from "@/lib/db";
import { serializeModelRuntimeState } from "@/lib/runtime/model-state";
import {
  decideHealthHttpStatus,
  decideHealthStatusLabel,
} from "@/lib/health/decide-health-status";

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
  let lmInitError: string | undefined;

  try {
    await ensureModelManagerInitialized();
    lmStudioConnected = await lmStudioHealthCheck();
    modelState = serializeModelRuntimeState(getModelManager().getState());
  } catch (error) {
    lmInitError = error instanceof Error ? error.message : String(error);
    lmStudioConnected = false;
  }

  const modelLoaded =
    modelState.phase === "ready" && !!modelState.currentModel;
  const aiReady = lmStudioConnected && modelLoaded;
  const status = decideHealthStatusLabel({
    sqliteOk: sqlite.ok,
    lmStudioConnected,
  });
  const httpStatus = decideHealthHttpStatus({ sqliteOk: sqlite.ok });

  return Response.json(
    {
      status,
      ready: sqlite.ok,
      aiReady,
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
      ...(lmInitError ? { message: lmInitError } : {}),
      timestamp: new Date().toISOString(),
    },
    { status: httpStatus }
  );
}
