import { describe, expect, it } from "vitest";
import {
  redactEmailBody,
  redactSecretsInObject,
  redactToken,
  safeJsonStringify,
} from "./redact";

describe("observability redact", () => {
  it("redactToken masque le milieu", () => {
    expect(redactToken("abcdefghijklmnop")).toBe("abcd…mnop");
    expect(redactToken("short")).toBe("[redacted]");
  });

  it("redactEmailBody sans preview", () => {
    expect(redactEmailBody("contenu secret")).toBe("[redacted]");
  });

  it("redactEmailBody avec preview tronqué", () => {
    expect(redactEmailBody("hello world", 5)).toBe("hello…");
  });

  it("redactSecretsInObject masque les clés sensibles", () => {
    const result = redactSecretsInObject({
      draftId: "d1",
      confirmationToken: "super-secret-token-value",
      access_token: "at-1234567890",
      nested: { refresh_token: "rt-abcdef" },
    }) as Record<string, unknown>;

    expect(result.draftId).toBe("d1");
    expect(result.confirmationToken).toMatch(/…/);
    expect(result.access_token).toMatch(/…/);
    expect((result.nested as Record<string, unknown>).refresh_token).toMatch(
      /…|\[redacted\]/
    );
  });

  it("safeJsonStringify ne fuit pas les tokens", () => {
    const json = safeJsonStringify({
      confirmationToken: "never-leak-this-token",
    });
    expect(json).not.toContain("never-leak-this-token");
  });
});
