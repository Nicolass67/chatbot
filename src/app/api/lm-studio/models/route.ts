export const runtime = "nodejs";

import { getLocalAIRuntime } from "@/lib/runtime/factory";
import { lmStudioGetNativeModels } from "@/lib/runtime/reasoning";
import { isSelectableChatModel } from "@/lib/models/chat-models";

export async function GET() {
  try {
    const runtime = getLocalAIRuntime();
    const [models, nativeModels] = await Promise.all([
      runtime.getModels(),
      lmStudioGetNativeModels().catch(() => []),
    ]);

    const nativeByKey = new Map(nativeModels.map((m) => [m.key, m]));

    const data = models
      .filter((m) => isSelectableChatModel(m.id, m.name))
      .map((m) => {
      const native = nativeByKey.get(m.id);
      return {
        id: m.id,
        name: native?.display_name ?? m.name ?? m.id,
        vision: native?.capabilities?.vision ?? false,
        toolCalling: native?.capabilities?.trained_for_tool_use ?? true,
        reasoning: native?.capabilities?.reasoning ?? null,
      };
    });

    return Response.json({ data });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Erreur" },
      { status: 502 }
    );
  }
}
