import { describe, expect, it } from "vitest";
import {
  API_ERROR_CODES,
  apiErrorBody,
  apiErrorResponse,
  assertApiErrorShape,
  normalizeApiErrorCode,
} from "./api-error";

describe("api-error", () => {
  it("builds body with error + code", () => {
    expect(apiErrorBody("NOT_FOUND", "Introuvable")).toEqual({
      error: "Introuvable",
      code: "NOT_FOUND",
    });
  });

  it("assertApiErrorShape accepts catalogue codes", () => {
    for (const code of API_ERROR_CODES) {
      expect(() =>
        assertApiErrorShape({ error: "x", code })
      ).not.toThrow();
    }
  });

  it("assertApiErrorShape rejects missing code", () => {
    expect(() => assertApiErrorShape({ error: "x" })).toThrow(/invalid code/i);
  });

  it("normalizeApiErrorCode maps unknown to INTERNAL", () => {
    expect(normalizeApiErrorCode("EMAIL_NOT_CONNECTED")).toBe(
      "EMAIL_NOT_CONNECTED"
    );
    expect(normalizeApiErrorCode("WEIRD")).toBe("INTERNAL");
  });

  it("apiErrorResponse sets default status", async () => {
    const res = apiErrorResponse("AUTH_REQUIRED", "Non autorisé");
    expect(res.status).toBe(401);
    const body = await res.json();
    assertApiErrorShape(body);
  });
});
