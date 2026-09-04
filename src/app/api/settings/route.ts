export const runtime = "nodejs";

import { getSettings, updateSettings, appSettingsSchema } from "@/lib/settings/service";

export async function GET() {
  const settings = await getSettings();
  return Response.json(settings);
}

export async function PATCH(request: Request) {
  try {
    const body = await request.json();
    const partial = appSettingsSchema.partial().parse(body);
    const settings = await updateSettings(partial);
    return Response.json(settings);
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Invalid settings" },
      { status: 400 }
    );
  }
}
