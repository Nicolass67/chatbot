import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  buildMultimodalUserMessage,
  parseStoredMessageContent,
  serializeContentForStorage,
} from "@/lib/attachments/multimodal";
import type { Attachment } from "@/lib/db/schema";

const tempFiles: string[] = [];

afterEach(() => {
  for (const f of tempFiles) {
    try {
      fs.unlinkSync(f);
    } catch {
      // ignore
    }
  }
  tempFiles.length = 0;
});

describe("multimodal payload", () => {
  it("serializes and parses message with attachments", () => {
    const raw = serializeContentForStorage("Analyse cette image", ["att1", "att2"]);
    const parsed = parseStoredMessageContent(raw);
    expect(parsed.text).toBe("Analyse cette image");
    expect(parsed.attachmentIds).toEqual(["att1", "att2"]);
  });

  it("builds OpenAI-compatible multimodal message", () => {
    const tmp = path.join(os.tmpdir(), `test-${Date.now()}.png`);
    fs.writeFileSync(tmp, Buffer.from([0x89, 0x50, 0x4e, 0x47]));
    tempFiles.push(tmp);

    const attachment: Attachment = {
      id: "img1",
      conversationId: "conv1",
      messageId: null,
      type: "image",
      filename: "test.png",
      mimeType: "image/png",
      localPath: tmp,
      sizeBytes: 4,
      status: "pending",
      extractedCharCount: 0,
      createdAt: new Date().toISOString(),
    };

    const msg = buildMultimodalUserMessage("Describe", [attachment]);
    expect(msg.role).toBe("user");
    expect(Array.isArray(msg.content)).toBe(true);

    const parts = msg.content as Array<{ type: string; text?: string; image_url?: { url: string } }>;
    expect(parts[0]?.type).toBe("text");
    expect(parts[0]?.text).toBe("Describe");
    expect(parts[1]?.type).toBe("image_url");
    expect(parts[1]?.image_url?.url).toMatch(/^data:image\/png;base64,/);
  });
});

describe("model capabilities", () => {
  it("detects vision from model name heuristics", async () => {
    const { getCapabilitiesFromModelId } = await import("@/lib/runtime/capabilities");
    const qwen = getCapabilitiesFromModelId("qwen2-vl-7b");
    expect(qwen.capabilities.vision).toBe(true);

    const textOnly = getCapabilitiesFromModelId("llama-3.2-3b");
    expect(textOnly.capabilities.vision).toBe(false);
    expect(textOnly.capabilities.text).toBe(true);
  });

  it("returns clear error when vision unsupported", async () => {
    const { assertVisionSupported } = await import("@/lib/runtime/capabilities");
    const err = assertVisionSupported(
      { text: true, vision: false, toolCalling: true, reasoning: false },
      1
    );
    expect(err).toContain("vision");
  });
});
