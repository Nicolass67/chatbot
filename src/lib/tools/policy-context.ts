import type { PermissionScope, PolicyContext } from "@/lib/policy";
import {
  defaultFilesGrantedPermissions,
} from "@/lib/policy/engine";
import { oauthScopesToGrantedPermissions } from "@/lib/policy/scopes";
import {
  getOAuthAccount,
  isEmailFeatureEnabled,
} from "@/lib/integrations/oauth";
import { isFilesFeatureEnabled } from "@/lib/files/feature";
import {
  ensureDefaultRoots,
  hasConfiguredRoots,
} from "@/lib/files/roots";

export async function resolveEmailPolicyContext(
  userId: string
): Promise<Pick<PolicyContext, "emailConnected" | "grantedPermissions">> {
  if (!isEmailFeatureEnabled()) {
    return { emailConnected: false, grantedPermissions: [] };
  }

  const account = await getOAuthAccount(userId, "gmail");
  if (!account) {
    return { emailConnected: false, grantedPermissions: [] };
  }

  const scopes = JSON.parse(account.scopesJson) as string[];
  const grantedPermissions: PermissionScope[] =
    oauthScopesToGrantedPermissions(scopes);

  return {
    emailConnected: true,
    grantedPermissions,
  };
}

export async function resolveCombinedPolicyContext(
  userId: string
): Promise<
  Pick<
    PolicyContext,
    | "emailConnected"
    | "grantedPermissions"
    | "filesEnabled"
    | "hasConfiguredRoots"
  >
> {
  const email = await resolveEmailPolicyContext(userId);
  const filesEnabled = isFilesFeatureEnabled();
  let configured = false;
  if (filesEnabled) {
    await ensureDefaultRoots(userId);
    configured = await hasConfiguredRoots(userId);
  }

  const filePerms = filesEnabled && configured
    ? defaultFilesGrantedPermissions()
    : [];

  return {
    emailConnected: email.emailConnected,
    grantedPermissions: [...(email.grantedPermissions ?? []), ...filePerms],
    filesEnabled,
    hasConfiguredRoots: configured,
  };
}
