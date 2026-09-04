export const runtime = "nodejs";

import { getActiveModelCapabilities } from "@/lib/runtime/capabilities";
import { getSettings } from "@/lib/settings/service";

export async function GET() {
  const settings = await getSettings();
  const info = await getActiveModelCapabilities(settings.selectedModel);
  return Response.json(info);
}
