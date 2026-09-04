import { describe, expect, it, vi } from "vitest";
import { resolveEmailPolicyContext } from "./policy-context";

vi.mock("@/lib/integrations/oauth", () => ({
  isEmailFeatureEnabled: vi.fn(() => true),
  getOAuthAccount: vi.fn(),
}));

describe("resolveEmailPolicyContext", () => {
  it("retourne déconnecté si email désactivé", async () => {
    const oauth = await import("@/lib/integrations/oauth");
    vi.mocked(oauth.isEmailFeatureEnabled).mockReturnValueOnce(false);

    await expect(resolveEmailPolicyContext("user-1")).resolves.toEqual({
      emailConnected: false,
      grantedPermissions: [],
    });
  });

  it("retourne permissions si compte Gmail présent", async () => {
    const oauth = await import("@/lib/integrations/oauth");
    vi.mocked(oauth.getOAuthAccount).mockResolvedValueOnce({
      id: "acc-1",
      userId: "user-1",
      provider: "gmail",
      accountEmail: "me@gmail.com",
      encryptedAccessToken: "enc",
      encryptedRefreshToken: null,
      expiresAt: null,
      scopesJson: JSON.stringify([
        "https://www.googleapis.com/auth/gmail.readonly",
        "https://www.googleapis.com/auth/gmail.compose",
      ]),
    });

    const ctx = await resolveEmailPolicyContext("user-1");
    expect(ctx.emailConnected).toBe(true);
    expect(ctx.grantedPermissions).toContain("READ_EMAIL");
    expect(ctx.grantedPermissions).toContain("CREATE_DRAFT");
  });
});
