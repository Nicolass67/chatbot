export const runtime = "nodejs";

import { ensureModelManagerInitialized } from "@/lib/lm-studio/model-manager";
import { getLocalAIRuntime } from "@/lib/runtime/factory";
import { serializeModelRuntimeState } from "@/lib/runtime/model-state";

export async function GET() {
  try {
    await ensureModelManagerInitialized();
    const runtime = getLocalAIRuntime();
    const status = await runtime.status();
    return Response.json({
      ...status,
      model: status.model
        ? serializeModelRuntimeState(status.model)
        : undefined,
    });
  } catch (error) {
    return Response.json(
      {
        status: "ERROR",
        modelLoaded: null,
        message: error instanceof Error ? error.message : "Erreur runtime",
      },
      { status: 500 }
    );
  }
}
