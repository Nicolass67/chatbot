export const runtime = "nodejs";

import { exportMemoriesJson } from "@/lib/memory/extract";

export async function GET() {
  const data = await exportMemoriesJson();
  return Response.json(data, {
    headers: {
      "Content-Disposition": 'attachment; filename="memories.json"',
    },
  });
}
