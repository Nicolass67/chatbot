import { describe, expect, it } from "vitest";
import { decryptSecret, encryptSecret, TokenEncryptionError } from "./token-crypto";

const TEST_KEY = Buffer.alloc(32, 7).toString("base64");

describe("token-crypto", () => {
  it("chiffre et déchiffre un secret", () => {
    const plaintext = "ya29.access-token-secret";
    const encrypted = encryptSecret(plaintext, TEST_KEY);
    expect(encrypted).not.toContain(plaintext);
    expect(decryptSecret(encrypted, TEST_KEY)).toBe(plaintext);
  });

  it("rejette une clé de taille invalide", () => {
    expect(() => encryptSecret("x", Buffer.alloc(16).toString("base64"))).toThrow(
      TokenEncryptionError
    );
  });

  it("rejette un ciphertext altéré", () => {
    const encrypted = encryptSecret("token", TEST_KEY);
    const buf = Buffer.from(encrypted, "base64");
    buf[buf.length - 1] ^= 0xff;
    expect(() =>
      decryptSecret(buf.toString("base64"), TEST_KEY)
    ).toThrow();
  });
});
