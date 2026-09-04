import { describe, expect, it } from "vitest";
import { offlineWakePageResponse, renderOfflineWakePage } from "./offline-page";

describe("offline wake page", () => {
  it("includes wake button and polling script", () => {
    const html = renderOfflineWakePage();
    expect(html).toContain("Allumer le PC");
    expect(html).toContain('fetch("/wake"');
    expect(html).toContain('fetch("/shutdown-pc"');
    expect(html).toContain('fetch("/status"');
    expect(html).not.toMatch(/app_token|session_token|password/i);
  });

  it("returns HTML 503 response", async () => {
    const response = offlineWakePageResponse();
    expect(response.status).toBe(503);
    expect(response.headers.get("content-type")).toContain("text/html");
    const html = await response.text();
    expect(html).toContain("Réveiller ou relancer");
    expect(html).toContain("Relancer les services");
  });
});
