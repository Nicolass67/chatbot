import { describe, expect, it } from "vitest";
import { evaluateActionConfirm, evaluateToolCall } from "./engine";
import { GMAIL_SCOPE_COMPOSE, GMAIL_SCOPE_READONLY } from "./scopes";
import type { PolicyContext } from "./types";

const baseCtx = (overrides: Partial<PolicyContext> = {}): PolicyContext => ({
  userId: "local",
  conversationId: "conv-1",
  emailConnected: false,
  grantedPermissions: [],
  ...overrides,
});

describe("evaluateToolCall", () => {
  it("autorise web_search sans compte email", () => {
    const decision = evaluateToolCall(
      {
        toolName: "web_search",
        params: { query: "test" },
        userId: "local",
        conversationId: "conv-1",
      },
      baseCtx()
    );
    expect(decision).toEqual({ outcome: "allow" });
  });

  it("refuse un outil inconnu", () => {
    const decision = evaluateToolCall(
      {
        toolName: "unknown_tool",
        params: {},
        userId: "local",
        conversationId: "conv-1",
      },
      baseCtx()
    );
    expect(decision.outcome).toBe("deny");
    if (decision.outcome === "deny") {
      expect(decision.code).toBe("UNKNOWN_TOOL");
    }
  });

  it("refuse email_list sans compte connecté", () => {
    const decision = evaluateToolCall(
      {
        toolName: "email_list",
        params: {},
        userId: "local",
        conversationId: "conv-1",
      },
      baseCtx()
    );
    expect(decision.outcome).toBe("deny");
    if (decision.outcome === "deny") {
      expect(decision.code).toBe("EMAIL_NOT_CONNECTED");
    }
  });

  it("autorise email_list avec compte et permissions", () => {
    const decision = evaluateToolCall(
      {
        toolName: "email_list",
        params: {},
        userId: "user-1",
        conversationId: "conv-1",
      },
      baseCtx({
        emailConnected: true,
        grantedPermissions: ["READ_EMAIL", "SEARCH_EMAIL"],
      })
    );
    expect(decision).toEqual({ outcome: "allow" });
  });

  it("autorise CREATE_DRAFT avec permissions", () => {
    const decision = evaluateToolCall(
      {
        toolName: "email_create_draft",
        params: { threadId: "t1" },
        userId: "user-1",
        conversationId: "conv-1",
      },
      baseCtx({
        emailConnected: true,
        grantedPermissions: ["READ_EMAIL", "CREATE_DRAFT"],
      })
    );
    expect(decision).toEqual({ outcome: "allow" });
  });

  it("refuse email_send sans confirmation explicite", () => {
    const decision = evaluateToolCall(
      {
        toolName: "email_send",
        params: { draftId: "d1" },
        userId: "user-1",
        conversationId: "conv-1",
      },
      baseCtx({
        emailConnected: true,
        grantedPermissions: ["SEND_EMAIL", "READ_EMAIL", "CREATE_DRAFT"],
      })
    );
    expect(decision.outcome).toBe("deny");
    if (decision.outcome === "deny") {
      expect(decision.code).toBe("CONFIRMATION_REQUIRED");
    }
  });

  it("autorise email_send avec confirmation explicite", () => {
    const decision = evaluateToolCall(
      {
        toolName: "email_send",
        params: { draftId: "d1" },
        userId: "user-1",
        conversationId: "conv-1",
      },
      baseCtx({
        emailConnected: true,
        grantedPermissions: ["SEND_EMAIL", "READ_EMAIL", "CREATE_DRAFT"],
        hasConfirmation: true,
      })
    );
    expect(decision).toEqual({ outcome: "allow" });
  });

  it("refuse si userId absent", () => {
    const decision = evaluateToolCall(
      {
        toolName: "web_search",
        params: {},
        userId: "",
        conversationId: "conv-1",
      },
      baseCtx({ userId: "" })
    );
    expect(decision.outcome).toBe("deny");
    if (decision.outcome === "deny") {
      expect(decision.code).toBe("UNAUTHENTICATED");
    }
  });
});

describe("evaluateActionConfirm", () => {
  const future = new Date(Date.now() + 60_000).toISOString();
  const past = new Date(Date.now() - 60_000).toISOString();

  it("refuse SEND sans confirmation explicite", () => {
    const decision = evaluateActionConfirm(
      {
        actionId: "a1",
        confirmationToken: "tok",
        userId: "user-1",
        payloadHash: "hash1",
      },
      {
        ...baseCtx({
          emailConnected: true,
          grantedPermissions: ["SEND_EMAIL"],
        }),
        expectedUserId: "user-1",
        expectedPayloadHash: "hash1",
        status: "pending_confirmation",
        expiresAt: future,
        confirmationAlreadyUsed: false,
        hasConfirmation: false,
      }
    );
    expect(decision.outcome).toBe("deny");
    if (decision.outcome === "deny") {
      expect(decision.code).toBe("CONFIRMATION_REQUIRED");
    }
  });

  it("autorise SEND avec confirmation valide", () => {
    const decision = evaluateActionConfirm(
      {
        actionId: "a1",
        confirmationToken: "tok",
        userId: "user-1",
        payloadHash: "hash1",
      },
      {
        ...baseCtx({
          emailConnected: true,
          grantedPermissions: ["SEND_EMAIL"],
        }),
        expectedUserId: "user-1",
        expectedPayloadHash: "hash1",
        status: "pending_confirmation",
        expiresAt: future,
        confirmationAlreadyUsed: false,
        hasConfirmation: true,
      }
    );
    expect(decision).toEqual({ outcome: "allow" });
  });

  it("refuse mauvais userId", () => {
    const decision = evaluateActionConfirm(
      {
        actionId: "a1",
        confirmationToken: "tok",
        userId: "attacker",
        payloadHash: "hash1",
      },
      {
        ...baseCtx({
          emailConnected: true,
          grantedPermissions: ["SEND_EMAIL"],
        }),
        expectedUserId: "user-1",
        expectedPayloadHash: "hash1",
        status: "pending_confirmation",
        expiresAt: future,
        confirmationAlreadyUsed: false,
        hasConfirmation: true,
      }
    );
    expect(decision.outcome).toBe("deny");
  });

  it("refuse confirmation expirée", () => {
    const decision = evaluateActionConfirm(
      {
        actionId: "a1",
        confirmationToken: "tok",
        userId: "user-1",
        payloadHash: "hash1",
      },
      {
        ...baseCtx({
          emailConnected: true,
          grantedPermissions: ["SEND_EMAIL"],
        }),
        expectedUserId: "user-1",
        expectedPayloadHash: "hash1",
        status: "pending_confirmation",
        expiresAt: past,
        confirmationAlreadyUsed: false,
        hasConfirmation: true,
      }
    );
    expect(decision.outcome).toBe("deny");
  });

  it("refuse confirmation déjà utilisée", () => {
    const decision = evaluateActionConfirm(
      {
        actionId: "a1",
        confirmationToken: "tok",
        userId: "user-1",
        payloadHash: "hash1",
      },
      {
        ...baseCtx({
          emailConnected: true,
          grantedPermissions: ["SEND_EMAIL"],
        }),
        expectedUserId: "user-1",
        expectedPayloadHash: "hash1",
        status: "pending_confirmation",
        expiresAt: future,
        confirmationAlreadyUsed: true,
        hasConfirmation: true,
      }
    );
    expect(decision.outcome).toBe("deny");
  });

  it("refuse hash modifié après confirmation", () => {
    const decision = evaluateActionConfirm(
      {
        actionId: "a1",
        confirmationToken: "tok",
        userId: "user-1",
        payloadHash: "hash-tampered",
      },
      {
        ...baseCtx({
          emailConnected: true,
          grantedPermissions: ["SEND_EMAIL"],
        }),
        expectedUserId: "user-1",
        expectedPayloadHash: "hash1",
        status: "pending_confirmation",
        expiresAt: future,
        confirmationAlreadyUsed: false,
        hasConfirmation: true,
      }
    );
    expect(decision.outcome).toBe("deny");
  });

  it("refuse TRASH sans permission TRASH_EMAIL", () => {
    const decision = evaluateActionConfirm(
      {
        actionId: "a1",
        confirmationToken: "tok",
        userId: "user-1",
        payloadHash: "hash1",
      },
      {
        ...baseCtx({
          emailConnected: true,
          grantedPermissions: ["READ_EMAIL", "SEND_EMAIL"],
        }),
        expectedUserId: "user-1",
        expectedPayloadHash: "hash1",
        status: "pending_confirmation",
        expiresAt: future,
        confirmationAlreadyUsed: false,
        hasConfirmation: true,
        actionType: "trash_email",
      }
    );
    expect(decision.outcome).toBe("deny");
    if (decision.outcome === "deny") {
      expect(decision.code).toBe("MISSING_PERMISSION");
    }
  });

  it("autorise TRASH avec TRASH_EMAIL et confirmation", () => {
    const decision = evaluateActionConfirm(
      {
        actionId: "a1",
        confirmationToken: "tok",
        userId: "user-1",
        payloadHash: "hash1",
      },
      {
        ...baseCtx({
          emailConnected: true,
          grantedPermissions: ["TRASH_EMAIL", "READ_EMAIL"],
        }),
        expectedUserId: "user-1",
        expectedPayloadHash: "hash1",
        status: "pending_confirmation",
        expiresAt: future,
        confirmationAlreadyUsed: false,
        hasConfirmation: true,
        actionType: "trash_email",
      }
    );
    expect(decision).toEqual({ outcome: "allow" });
  });
});

describe("Gmail OAuth scopes V1", () => {
  it("utilise readonly + compose", () => {
    expect(GMAIL_SCOPE_READONLY).toContain("gmail.readonly");
    expect(GMAIL_SCOPE_COMPOSE).toContain("gmail.compose");
  });
});
