import { describe, expect, it, vi } from "vitest";
import { emailSendInternalTool } from "./send";

const mockSendDraft = vi.fn();

vi.mock("@/lib/integrations/email", () => ({
  getEmailProvider: vi.fn(async () => ({
    sendDraft: mockSendDraft,
  })),
}));

vi.mock("@/lib/integrations/oauth/config", () => ({
  requireGoogleOAuthConfig: () => ({
    clientId: "test",
    clientSecret: "test",
    redirectUri: "http://localhost/callback",
    encryptionKey: Buffer.alloc(32, 1).toString("base64"),
    scopes: [],
  }),
}));

vi.mock("@/lib/email/draft/service", () => ({
  requireEmailDraftForUser: vi.fn(async () => ({
    id: "draft-1",
    status: "validated",
    providerDraftId: "gmail-draft-1",
  })),
}));

const baseCtx = {
  signal: AbortSignal.timeout(5000),
  settings: {} as import("@/lib/settings/service").AppSettings,
  conversationId: "conv-1",
  runtimeLocation: "local" as const,
  userId: "user-1",
};

describe("email_send internal tool", () => {
  it("envoie un brouillon validé via le provider", async () => {
    mockSendDraft.mockResolvedValueOnce({
      messageId: "sent-1",
      threadId: "thread-1",
    });

    const result = await emailSendInternalTool.execute(
      { draftId: "draft-1" },
      baseCtx
    );

    expect(mockSendDraft).toHaveBeenCalledWith("gmail-draft-1");
    expect(result).toMatchObject({
      draftId: "draft-1",
      messageId: "sent-1",
      threadId: "thread-1",
    });
  });
});
