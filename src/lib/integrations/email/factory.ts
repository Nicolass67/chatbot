import { refreshGmailAccessToken } from "@/lib/integrations/email/gmail/oauth";
import { GmailProvider } from "@/lib/integrations/email/gmail/provider";
import {
  EmailNotConnectedError,
  type EmailProvider,
} from "@/lib/integrations/email/types";
import {
  getOAuthAccount,
  getValidOAuthTokens,
  isGoogleOAuthConfigured,
} from "@/lib/integrations/oauth";

export async function getEmailProvider(userId: string): Promise<EmailProvider> {
  if (!isGoogleOAuthConfigured()) {
    throw new EmailNotConnectedError();
  }

  const account = await getOAuthAccount(userId, "gmail");
  if (!account) {
    throw new EmailNotConnectedError();
  }

  const tokens = await getValidOAuthTokens(
    userId,
    "gmail",
    refreshGmailAccessToken
  );

  return new GmailProvider(tokens.accessToken, account.accountEmail);
}

export async function isEmailProviderConnected(userId: string): Promise<boolean> {
  const account = await getOAuthAccount(userId, "gmail");
  return account !== null;
}
