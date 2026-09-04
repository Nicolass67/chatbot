export const runtime = "nodejs";

import { getReasoningCapabilities } from "@/lib/runtime/reasoning";
import { getSettings } from "@/lib/settings/service";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const modelParam = url.searchParams.get("model");
  const settings = await getSettings();
  const modelId = modelParam || settings.selectedModel;

  if (!modelId) {
    return Response.json({
      modelId: "",
      supported: false,
      kind: "none",
      modes: [],
      defaultModeId: null,
      transmissionMethod: null,
      source: "unknown",
    });
  }

  const info = await getReasoningCapabilities(modelId);
  return Response.json(info);
}
