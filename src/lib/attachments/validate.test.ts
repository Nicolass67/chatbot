import { describe, expect, it } from "vitest";
import { validateFile } from "@/lib/attachments/validate";

describe("validateFile", () => {
  it("accepts JPEG images", () => {
    const result = validateFile({
      filename: "photo.jpg",
      mimeType: "image/jpeg",
      sizeBytes: 1024,
    });
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.type).toBe("image");
  });

  it("accepts PDF documents", () => {
    const result = validateFile({
      filename: "doc.pdf",
      mimeType: "application/pdf",
      sizeBytes: 2048,
    });
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.type).toBe("document");
  });

  it("rejects unsupported types", () => {
    const result = validateFile({
      filename: "virus.exe",
      mimeType: "application/x-msdownload",
      sizeBytes: 100,
    });
    expect(result.ok).toBe(false);
  });

  it("rejects oversized files", () => {
    const result = validateFile({
      filename: "big.png",
      mimeType: "image/png",
      sizeBytes: 50 * 1024 * 1024,
      maxBytes: 20 * 1024 * 1024,
    });
    expect(result.ok).toBe(false);
  });

  it("rejects path traversal filenames", () => {
    const result = validateFile({
      filename: "../etc/passwd",
      mimeType: "text/plain",
      sizeBytes: 10,
    });
    expect(result.ok).toBe(false);
  });
});
