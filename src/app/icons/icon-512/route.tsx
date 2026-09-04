import { renderAppIcon } from "@/lib/pwa/app-icon";

export async function GET() {
  return renderAppIcon(512);
}
