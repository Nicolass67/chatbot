import { describe, expect, it } from "vitest";
import {
  isHealthCheckPath,
  isInternalHealthAuthorized,
  isAppSessionBearerHeader,
} from "./request-auth-edge";

describe("request-auth health bypass", () => {
  it("identifie le chemin health", () => {
    expect(isHealthCheckPath("/api/health")).toBe(true);
    expect(isHealthCheckPath("/api/chat")).toBe(false);
  });

  it("autorise le health check avec le token interne", () => {
    process.env.HEALTH_CHECK_TOKEN = "test-token-secret";
    const req = new Request("http://localhost/api/health", {
      headers: { Authorization: "Bearer test-token-secret" },
    });
    expect(isInternalHealthAuthorized(req)).toBe(true);
    delete process.env.HEALTH_CHECK_TOKEN;
  });

  it("refuse un token app session comme health token", () => {
    process.env.HEALTH_CHECK_TOKEN = "test-token-secret";
    const req = new Request("http://localhost/api/health", {
      headers: { Authorization: "Bearer chs_not_health" },
    });
    expect(isInternalHealthAuthorized(req)).toBe(false);
    delete process.env.HEALTH_CHECK_TOKEN;
  });

  it("détecte Bearer app session", () => {
    const req = new Request("http://localhost/api/chat", {
      headers: { Authorization: "Bearer chs_abc" },
    });
    expect(isAppSessionBearerHeader(req)).toBe(true);
  });
});
