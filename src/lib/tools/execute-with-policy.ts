import {
  applyTaintFromToolOutput,
  evaluateToolCall,
  getToolMetadata,
  PolicyDeniedError,
  type PolicyContext,
  type TaintState,
} from "@/lib/policy";
import { executeToolRaw } from "./registry";
import type { ToolContext } from "./types";

function resolveUserId(ctx: ToolContext): string {
  return ctx.userId?.trim() || "local";
}

function buildPolicyContext(ctx: ToolContext): PolicyContext {
  return {
    userId: resolveUserId(ctx),
    conversationId: ctx.conversationId,
    emailConnected: ctx.policyContext?.emailConnected ?? false,
    grantedPermissions: ctx.policyContext?.grantedPermissions ?? [],
    hasConfirmation: ctx.policyContext?.hasConfirmation ?? false,
    filesEnabled: ctx.policyContext?.filesEnabled ?? false,
    hasConfiguredRoots: ctx.policyContext?.hasConfiguredRoots ?? false,
  };
}

export async function executeToolWithPolicy(
  name: string,
  args: unknown,
  ctx: ToolContext
): Promise<unknown> {
  const userId = resolveUserId(ctx);
  const policyCtx = buildPolicyContext(ctx);

  const decision = evaluateToolCall(
    {
      toolName: name,
      params: args,
      userId,
      conversationId: ctx.conversationId,
    },
    policyCtx
  );

  if (decision.outcome === "deny") {
    throw new PolicyDeniedError(decision.code, decision.reason);
  }

  if (decision.outcome === "pending_confirmation") {
    throw new PolicyDeniedError(
      "CONFIRMATION_REQUIRED",
      decision.reason
    );
  }

  const result = await executeToolRaw(name, args, { ...ctx, userId });

  const metadata = getToolMetadata(name);
  const taintState = ctx.taintState;
  if (metadata?.taintPolicy === "output_untrusted" && taintState) {
    Object.assign(
      taintState,
      applyTaintFromToolOutput(taintState, name, metadata.taintPolicy)
    );
  }

  return result;
}

export { PolicyDeniedError, type TaintState };
