import { describe, expect, it, vi } from "vitest";
import { PolicyDeniedError } from "@/lib/policy";
import { executeToolWithPolicy } from "./execute-with-policy";

vi.mock("./registry", () => ({
  executeToolRaw: vi.fn(async () => ({ ok: true })),
}));

const baseCtx = {
  signal: AbortSignal.timeout(5000),
  settings: {} as import("@/lib/settings/service").AppSettings,
  conversationId: "conv-1",
  runtimeLocation: "local" as const,
};

describe("executeToolWithPolicy", () => {
  it("autorise web_search (pass-through)", async () => {
    const result = await executeToolWithPolicy(
      "web_search",
      { query: "test" },
      baseCtx
    );
    expect(result).toEqual({ ok: true });
  });

  it("bloque email_send sans confirmation", async () => {
    await expect(
      executeToolWithPolicy(
        "email_send",
        { draftId: "d1" },
        {
          ...baseCtx,
          userId: "user-1",
          policyContext: {
            emailConnected: true,
            grantedPermissions: ["SEND_EMAIL"],
          },
        }
      )
    ).rejects.toBeInstanceOf(PolicyDeniedError);
  });

  it("bloque email_list sans OAuth", async () => {
    await expect(
      executeToolWithPolicy("email_list", {}, baseCtx)
    ).rejects.toMatchObject({
      code: "EMAIL_NOT_CONNECTED",
    });
  });

  it("autorise email_send avec confirmation explicite", async () => {
    const { executeToolRaw } = await import("./registry");
    vi.mocked(executeToolRaw).mockResolvedValueOnce({
      draftId: "d1",
      messageId: "m1",
      threadId: "t1",
    });

    const result = await executeToolWithPolicy(
      "email_send",
      { draftId: "d1" },
      {
        ...baseCtx,
        userId: "user-1",
        policyContext: {
          emailConnected: true,
          grantedPermissions: ["SEND_EMAIL"],
          hasConfirmation: true,
        },
      }
    );

    expect(result).toEqual({
      draftId: "d1",
      messageId: "m1",
      threadId: "t1",
    });
  });
});
