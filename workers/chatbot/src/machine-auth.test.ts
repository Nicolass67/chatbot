import { describe, expect, it } from "vitest";
import {
  extractBearerToken,
  verifyBootMachineToken,
} from "./machine-auth";

describe("machine auth", () => {
  it("extracts bearer token", () => {
    const req = new Request("https://example.com", {
      headers: { Authorization: "Bearer abc123" },
    });
    expect(extractBearerToken(req)).toBe("abc123");
  });

  it("rejects missing bearer", () => {
    const req = new Request("https://example.com");
    expect(verifyBootMachineToken(req, "secret")).toBe(false);
  });

  it("accepts matching token", () => {
    const req = new Request("https://example.com", {
      headers: { Authorization: "Bearer secret-value" },
    });
    expect(verifyBootMachineToken(req, "secret-value")).toBe(true);
  });

  it("rejects wrong token", () => {
    const req = new Request("https://example.com", {
      headers: { Authorization: "Bearer other" },
    });
    expect(verifyBootMachineToken(req, "secret-value")).toBe(false);
  });
});
