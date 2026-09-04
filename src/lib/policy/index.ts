export {
  evaluateActionConfirm,
  evaluateToolCall,
  defaultFilesGrantedPermissions,
} from "./engine";
export {
  getLlmExposedToolNames,
  getToolMetadata,
  TOOL_METADATA,
} from "./metadata";
export {
  GMAIL_OAUTH_SCOPES,
  GMAIL_SCOPE_COMPOSE,
  GMAIL_SCOPE_MODIFY,
  GMAIL_SCOPE_READONLY,
  GMAIL_TRASH_REQUIRED_SCOPES,
  GMAIL_V1_OAUTH_SCOPES,
  PERMISSION_TO_GMAIL_SCOPES,
  hasRequiredOAuthScopes,
  oauthScopesToGrantedPermissions,
} from "./scopes";
export {
  applyTaintFromToolOutput,
  createTaintState,
  markUntrustedRead,
  type TaintState,
} from "./taint";
export {
  PolicyDeniedError,
  type ActionConfirmation,
  type ActionProposal,
  type PermissionScope,
  type PolicyContext,
  type PolicyDecision,
  type PolicyDenyCode,
  type RiskLevel,
  type ToolMetadata,
} from "./types";
