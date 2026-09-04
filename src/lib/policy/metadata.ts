import type { ToolMetadata } from "./types";

const WEB_SEARCH: ToolMetadata = {
  name: "web_search",
  domain: "web",
  requiredPermissions: [],
  riskLevel: "safe",
  exposedToLlm: true,
  requiresConfirmation: false,
  timeoutMs: 30_000,
  maxRetries: 1,
  taintPolicy: "output_untrusted",
};

const EMAIL_LIST: ToolMetadata = {
  name: "email_list",
  domain: "email",
  requiredPermissions: ["READ_EMAIL"],
  riskLevel: "safe",
  exposedToLlm: true,
  requiresConfirmation: false,
  timeoutMs: 15_000,
  maxRetries: 1,
  taintPolicy: "output_untrusted",
};

const EMAIL_SEARCH: ToolMetadata = {
  name: "email_search",
  domain: "email",
  requiredPermissions: ["SEARCH_EMAIL"],
  riskLevel: "safe",
  exposedToLlm: true,
  requiresConfirmation: false,
  timeoutMs: 15_000,
  maxRetries: 1,
  taintPolicy: "output_untrusted",
};

const EMAIL_GET_THREAD: ToolMetadata = {
  name: "email_get_thread",
  domain: "email",
  requiredPermissions: ["READ_EMAIL"],
  riskLevel: "safe",
  exposedToLlm: true,
  requiresConfirmation: false,
  timeoutMs: 20_000,
  maxRetries: 1,
  taintPolicy: "output_untrusted",
};

const EMAIL_ANALYZE: ToolMetadata = {
  name: "email_analyze",
  domain: "email",
  requiredPermissions: ["ANALYZE_EMAIL"],
  riskLevel: "moderate",
  exposedToLlm: true,
  requiresConfirmation: false,
  timeoutMs: 60_000,
  maxRetries: 0,
  taintPolicy: "output_untrusted",
};

const EMAIL_CREATE_DRAFT: ToolMetadata = {
  name: "email_create_draft",
  domain: "email",
  requiredPermissions: ["CREATE_DRAFT"],
  riskLevel: "moderate",
  exposedToLlm: true,
  requiresConfirmation: false,
  confirmationType: "preview",
  timeoutMs: 45_000,
  maxRetries: 0,
  taintPolicy: "none",
};

const EMAIL_SEND: ToolMetadata = {
  name: "email_send",
  domain: "email",
  requiredPermissions: ["SEND_EMAIL"],
  riskLevel: "critical",
  exposedToLlm: false,
  requiresConfirmation: true,
  confirmationType: "explicit_api",
  timeoutMs: 30_000,
  maxRetries: 0,
  taintPolicy: "none",
};

const FILE_SEARCH: ToolMetadata = {
  name: "file_search",
  domain: "files",
  requiredPermissions: ["SEARCH_FILES"],
  riskLevel: "safe",
  exposedToLlm: true,
  requiresConfirmation: false,
  timeoutMs: 30_000,
  maxRetries: 1,
  taintPolicy: "output_untrusted",
};

const FILE_LIST: ToolMetadata = {
  name: "file_list",
  domain: "files",
  requiredPermissions: ["READ_FILE"],
  riskLevel: "safe",
  exposedToLlm: true,
  requiresConfirmation: false,
  timeoutMs: 15_000,
  maxRetries: 1,
  taintPolicy: "output_untrusted",
};

const FILE_STAT: ToolMetadata = {
  name: "file_stat",
  domain: "files",
  requiredPermissions: ["READ_FILE"],
  riskLevel: "safe",
  exposedToLlm: true,
  requiresConfirmation: false,
  timeoutMs: 10_000,
  maxRetries: 1,
  taintPolicy: "none",
};

const FILE_READ: ToolMetadata = {
  name: "file_read",
  domain: "files",
  requiredPermissions: ["READ_FILE"],
  riskLevel: "safe",
  exposedToLlm: true,
  requiresConfirmation: false,
  timeoutMs: 45_000,
  maxRetries: 0,
  taintPolicy: "output_untrusted",
};

const FILE_ANALYZE: ToolMetadata = {
  name: "file_analyze",
  domain: "files",
  requiredPermissions: ["ANALYZE_FILE"],
  riskLevel: "moderate",
  exposedToLlm: true,
  requiresConfirmation: false,
  timeoutMs: 90_000,
  maxRetries: 0,
  taintPolicy: "output_untrusted",
};

const FILE_CREATE_DIRECTORY: ToolMetadata = {
  name: "file_create_directory",
  domain: "files",
  requiredPermissions: ["CREATE_DIRECTORY"],
  riskLevel: "moderate",
  exposedToLlm: true,
  requiresConfirmation: true,
  confirmationType: "explicit_api",
  timeoutMs: 15_000,
  maxRetries: 0,
  taintPolicy: "none",
};

const FILE_RENAME: ToolMetadata = {
  name: "file_rename",
  domain: "files",
  requiredPermissions: ["RENAME_FILE"],
  riskLevel: "moderate",
  exposedToLlm: true,
  requiresConfirmation: true,
  confirmationType: "explicit_api",
  timeoutMs: 15_000,
  maxRetries: 0,
  taintPolicy: "none",
};

const FILE_MOVE: ToolMetadata = {
  name: "file_move",
  domain: "files",
  requiredPermissions: ["MOVE_FILE"],
  riskLevel: "moderate",
  exposedToLlm: true,
  requiresConfirmation: true,
  confirmationType: "explicit_api",
  timeoutMs: 20_000,
  maxRetries: 0,
  taintPolicy: "none",
};

export const TOOL_METADATA: Record<string, ToolMetadata> = {
  web_search: WEB_SEARCH,
  email_list: EMAIL_LIST,
  email_search: EMAIL_SEARCH,
  email_get_thread: EMAIL_GET_THREAD,
  email_analyze: EMAIL_ANALYZE,
  email_create_draft: EMAIL_CREATE_DRAFT,
  email_send: EMAIL_SEND,
  file_search: FILE_SEARCH,
  file_list: FILE_LIST,
  file_stat: FILE_STAT,
  file_read: FILE_READ,
  file_analyze: FILE_ANALYZE,
  file_create_directory: FILE_CREATE_DIRECTORY,
  file_rename: FILE_RENAME,
  file_move: FILE_MOVE,
};

export function getToolMetadata(toolName: string): ToolMetadata | undefined {
  return TOOL_METADATA[toolName];
}

export function getLlmExposedToolNames(): string[] {
  return Object.values(TOOL_METADATA)
    .filter((m) => m.exposedToLlm)
    .map((m) => m.name);
}
