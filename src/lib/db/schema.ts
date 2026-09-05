import { relations, sql } from "drizzle-orm";
import {
  index,
  integer,
  real,
  sqliteTable,
  text,
  uniqueIndex,
} from "drizzle-orm/sqlite-core";

export const conversations = sqliteTable("conversations", {
  id: text("id").primaryKey(),
  title: text("title").notNull().default("Nouvelle conversation"),
  titleSource: text("title_source", { enum: ["auto", "user"] })
    .notNull()
    .default("auto"),
  reasoningEffort: text("reasoning_effort"),
  chatMode: text("chat_mode", { enum: ["chat", "agent"] })
    .notNull()
    .default("chat"),
  agentDepth: text("agent_depth", {
    enum: ["fast", "standard", "thorough"],
  })
    .notNull()
    .default("standard"),
  /** ConversationScope: general | mail | files */
  scope: text("scope", { enum: ["general", "mail", "files"] })
    .notNull()
    .default("general"),
  contextKey: text("context_key"),
  contextLabel: text("context_label"),
  createdAt: text("created_at")
    .notNull()
    .default(sql`(datetime('now'))`),
  updatedAt: text("updated_at")
    .notNull()
    .default(sql`(datetime('now'))`),
});

export const messages = sqliteTable(
  "messages",
  {
    id: text("id").primaryKey(),
    conversationId: text("conversation_id")
      .notNull()
      .references(() => conversations.id, { onDelete: "cascade" }),
    role: text("role", { enum: ["user", "assistant", "system", "tool"] }).notNull(),
    content: text("content").notNull(),
    createdAt: text("created_at")
      .notNull()
      .default(sql`(datetime('now'))`),
  },
  (table) => [
    index("messages_conversation_id_idx").on(table.conversationId, table.createdAt),
  ]
);

export const attachments = sqliteTable("attachments", {
  id: text("id").primaryKey(),
  conversationId: text("conversation_id")
    .notNull()
    .references(() => conversations.id, { onDelete: "cascade" }),
  messageId: text("message_id").references(() => messages.id, {
    onDelete: "cascade",
  }),
  type: text("type", { enum: ["image", "document"] }).notNull(),
  filename: text("filename").notNull(),
  mimeType: text("mime_type").notNull(),
  localPath: text("local_path").notNull(),
  sizeBytes: integer("size_bytes").notNull().default(0),
  status: text("status", { enum: ["pending", "attached"] })
    .notNull()
    .default("pending"),
  extractedCharCount: integer("extracted_char_count").notNull().default(0),
  createdAt: text("created_at")
    .notNull()
    .default(sql`(datetime('now'))`),
});

export const documentChunks = sqliteTable("document_chunks", {
  id: text("id").primaryKey(),
  attachmentId: text("attachment_id")
    .notNull()
    .references(() => attachments.id, { onDelete: "cascade" }),
  conversationId: text("conversation_id")
    .notNull()
    .references(() => conversations.id, { onDelete: "cascade" }),
  chunkIndex: integer("chunk_index").notNull(),
  content: text("content").notNull(),
  tokenEstimate: integer("token_estimate").notNull().default(0),
  createdAt: text("created_at")
    .notNull()
    .default(sql`(datetime('now'))`),
});

export const toolCalls = sqliteTable("tool_calls", {
  id: text("id").primaryKey(),
  conversationId: text("conversation_id")
    .notNull()
    .references(() => conversations.id, { onDelete: "cascade" }),
  messageId: text("message_id").references(() => messages.id, {
    onDelete: "set null",
  }),
  toolName: text("tool_name").notNull(),
  input: text("input").notNull(),
  output: text("output").notNull().default(""),
  status: text("status", { enum: ["pending", "success", "error"] })
    .notNull()
    .default("pending"),
  error: text("error"),
  durationMs: integer("duration_ms").notNull().default(0),
  createdAt: text("created_at")
    .notNull()
    .default(sql`(datetime('now'))`),
});

export const messageSources = sqliteTable("message_sources", {
  id: text("id").primaryKey(),
  messageId: text("message_id")
    .notNull()
    .references(() => messages.id, { onDelete: "cascade" }),
  toolCallId: text("tool_call_id").references(() => toolCalls.id, {
    onDelete: "cascade",
  }),
  title: text("title").notNull(),
  domain: text("domain").notNull(),
  url: text("url").notNull(),
  snippet: text("snippet"),
  createdAt: text("created_at")
    .notNull()
    .default(sql`(datetime('now'))`),
});

export const conversationSummaries = sqliteTable(
  "conversation_summaries",
  {
    id: text("id").primaryKey(),
    conversationId: text("conversation_id")
      .notNull()
      .references(() => conversations.id, { onDelete: "cascade" }),
    content: text("content").notNull(),
    coversUntilMessageId: text("covers_until_message_id").references(
      () => messages.id,
      { onDelete: "set null" }
    ),
    tokenEstimate: integer("token_estimate").notNull().default(0),
    createdAt: text("created_at")
      .notNull()
      .default(sql`(datetime('now'))`),
    updatedAt: text("updated_at")
      .notNull()
      .default(sql`(datetime('now'))`),
  },
  (table) => [
    uniqueIndex("conversation_summaries_conversation_id_idx").on(
      table.conversationId
    ),
  ]
);

export const memories = sqliteTable("memories", {
  id: text("id").primaryKey(),
  content: text("content").notNull(),
  category: text("category").notNull(),
  importance: real("importance").notNull().default(0.5),
  embedding: text("embedding"),
  createdAt: text("created_at")
    .notNull()
    .default(sql`(datetime('now'))`),
  updatedAt: text("updated_at")
    .notNull()
    .default(sql`(datetime('now'))`),
});

export const modelProfiles = sqliteTable("model_profiles", {
  modelId: text("model_id").primaryKey(),
  displayName: text("display_name").notNull(),
  temperature: real("temperature"),
  maxTokens: integer("max_tokens"),
  contextLength: integer("context_length"),
  updatedAt: text("updated_at")
    .notNull()
    .default(sql`(datetime('now'))`),
});

export const appSettings = sqliteTable("app_settings", {
  key: text("key").primaryKey(),
  value: text("value").notNull(),
});

export const agentRuns = sqliteTable("agent_runs", {
  id: text("id").primaryKey(),
  conversationId: text("conversation_id")
    .notNull()
    .references(() => conversations.id, { onDelete: "cascade" }),
  messageId: text("message_id").references(() => messages.id, {
    onDelete: "set null",
  }),
  depth: text("depth", { enum: ["fast", "standard", "thorough"] }).notNull(),
  model: text("model").notNull(),
  startedAt: text("started_at").notNull(),
  endedAt: text("ended_at"),
  status: text("status", {
    enum: ["running", "completed", "stopped", "limit_reached", "error"],
  }).notNull(),
  stepsJson: text("steps_json").notNull().default("[]"),
  statsJson: text("stats_json").notNull().default("{}"),
  limitReason: text("limit_reason"),
});

export const oauthAccounts = sqliteTable(
  "oauth_accounts",
  {
    id: text("id").primaryKey(),
    userId: text("user_id").notNull(),
    provider: text("provider", { enum: ["gmail"] }).notNull(),
    accountEmail: text("account_email").notNull(),
    encryptedAccessToken: text("encrypted_access_token").notNull(),
    encryptedRefreshToken: text("encrypted_refresh_token"),
    expiresAt: text("expires_at"),
    scopesJson: text("scopes_json").notNull(),
    createdAt: text("created_at")
      .notNull()
      .default(sql`(datetime('now'))`),
    updatedAt: text("updated_at")
      .notNull()
      .default(sql`(datetime('now'))`),
  },
  (table) => [
    uniqueIndex("oauth_accounts_user_provider_idx").on(
      table.userId,
      table.provider
    ),
  ]
);

/** Sessions Bearer pour clients natifs (Swift) — token stocké hashé. */
export const appSessions = sqliteTable(
  "app_sessions",
  {
    id: text("id").primaryKey(),
    userId: text("user_id").notNull(),
    tokenHash: text("token_hash").notNull(),
    expiresAt: text("expires_at").notNull(),
    createdAt: text("created_at")
      .notNull()
      .default(sql`(datetime('now'))`),
    revokedAt: text("revoked_at"),
    userAgent: text("user_agent"),
    client: text("client"),
  },
  (table) => [
    uniqueIndex("app_sessions_token_hash_idx").on(table.tokenHash),
    index("app_sessions_user_id_idx").on(table.userId),
  ]
);

export const emailDrafts = sqliteTable("email_drafts", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull(),
  conversationId: text("conversation_id")
    .notNull()
    .references(() => conversations.id, { onDelete: "cascade" }),
  threadId: text("thread_id"),
  provider: text("provider", { enum: ["gmail"] }).notNull(),
  providerDraftId: text("provider_draft_id"),
  toJson: text("to_json").notNull().default("[]"),
  ccJson: text("cc_json").notNull().default("[]"),
  bccJson: text("bcc_json").notNull().default("[]"),
  subject: text("subject").notNull().default(""),
  bodyText: text("body_text").notNull().default(""),
  bodyHtml: text("body_html"),
  attachmentIdsJson: text("attachment_ids_json").notNull().default("[]"),
  contentHash: text("content_hash").notNull(),
  status: text("status", {
    enum: ["draft", "validated", "sent", "cancelled"],
  })
    .notNull()
    .default("draft"),
  inReplyToMessageId: text("in_reply_to_message_id"),
  createdAt: text("created_at")
    .notNull()
    .default(sql`(datetime('now'))`),
  updatedAt: text("updated_at")
    .notNull()
    .default(sql`(datetime('now'))`),
});

export const pendingActions = sqliteTable(
  "pending_actions",
  {
    id: text("id").primaryKey(),
    userId: text("user_id").notNull(),
    conversationId: text("conversation_id")
      .notNull()
      .references(() => conversations.id, { onDelete: "cascade" }),
    draftId: text("draft_id").references(() => emailDrafts.id, {
      onDelete: "set null",
    }),
    resourceId: text("resource_id"),
    actionType: text("action_type", {
      enum: [
        "send_email",
        "trash_email",
        "create_directory",
        "rename_file",
        "move_file",
        "delete_file",
      ],
    }).notNull(),
    status: text("status", {
      enum: [
        "proposed",
        "pending_confirmation",
        "confirmed",
        "executing",
        "completed",
        "rejected",
        "cancelled",
        "expired",
        "failed",
      ],
    }).notNull(),
    payloadHash: text("payload_hash").notNull(),
    payloadJson: text("payload_json"),
    confirmationToken: text("confirmation_token").notNull().unique(),
    expiresAt: text("expires_at").notNull(),
    confirmedAt: text("confirmed_at"),
    executedAt: text("executed_at"),
    idempotencyKey: text("idempotency_key").notNull().unique(),
    errorCode: text("error_code"),
    errorMessage: text("error_message"),
    createdAt: text("created_at")
      .notNull()
      .default(sql`(datetime('now'))`),
  },
  (table) => [
    index("pending_actions_conversation_status_idx").on(
      table.conversationId,
      table.status
    ),
  ]
);

export const actionAuditLog = sqliteTable("action_audit_log", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull(),
  actionType: text("action_type").notNull(),
  resourceType: text("resource_type").notNull(),
  resourceId: text("resource_id").notNull(),
  status: text("status", {
    enum: ["success", "rejected", "failed"],
  }).notNull(),
  metadataJson: text("metadata_json").notNull().default("{}"),
  createdAt: text("created_at")
    .notNull()
    .default(sql`(datetime('now'))`),
});

export const fileRoots = sqliteTable(
  "file_roots",
  {
    id: text("id").primaryKey(),
    userId: text("user_id").notNull(),
    label: text("label").notNull(),
    absolutePath: text("absolute_path").notNull(),
    enabled: integer("enabled", { mode: "boolean" }).notNull().default(true),
    isDefault: integer("is_default", { mode: "boolean" })
      .notNull()
      .default(false),
    createdAt: text("created_at")
      .notNull()
      .default(sql`(datetime('now'))`),
  },
  (table) => [
    index("file_roots_user_idx").on(table.userId),
    uniqueIndex("file_roots_user_path_idx").on(
      table.userId,
      table.absolutePath
    ),
  ]
);

export const fileReferences = sqliteTable(
  "file_references",
  {
    id: text("id").primaryKey(),
    userId: text("user_id").notNull(),
    rootId: text("root_id")
      .notNull()
      .references(() => fileRoots.id, { onDelete: "cascade" }),
    relativePath: text("relative_path").notNull(),
    displayName: text("display_name").notNull(),
    sizeBytes: integer("size_bytes").notNull().default(0),
    mtimeMs: integer("mtime_ms").notNull().default(0),
    createdAt: text("created_at")
      .notNull()
      .default(sql`(datetime('now'))`),
    expiresAt: text("expires_at").notNull(),
  },
  (table) => [
    index("file_references_user_idx").on(table.userId),
    index("file_references_expires_idx").on(table.expiresAt),
    index("file_references_user_root_path_idx").on(
      table.userId,
      table.rootId,
      table.relativePath
    ),
  ]
);

export const fileIndexEntries = sqliteTable(
  "file_index_entries",
  {
    id: text("id").primaryKey(),
    userId: text("user_id").notNull(),
    rootId: text("root_id")
      .notNull()
      .references(() => fileRoots.id, { onDelete: "cascade" }),
    relativePath: text("relative_path").notNull(),
    sizeBytes: integer("size_bytes").notNull().default(0),
    mtimeMs: integer("mtime_ms").notNull().default(0),
    mime: text("mime").notNull().default("application/octet-stream"),
    contentHash: text("content_hash"),
    indexedAt: text("indexed_at")
      .notNull()
      .default(sql`(datetime('now'))`),
  },
  (table) => [
    uniqueIndex("file_index_entries_root_path_idx").on(
      table.rootId,
      table.relativePath
    ),
    index("file_index_entries_user_idx").on(table.userId),
    index("file_index_entries_user_root_idx").on(table.userId, table.rootId),
  ]
);

export const fileIndexChunks = sqliteTable(
  "file_index_chunks",
  {
    id: text("id").primaryKey(),
    entryId: text("entry_id")
      .notNull()
      .references(() => fileIndexEntries.id, { onDelete: "cascade" }),
    userId: text("user_id").notNull(),
    rootId: text("root_id").notNull(),
    chunkIndex: integer("chunk_index").notNull(),
    content: text("content").notNull(),
    createdAt: text("created_at")
      .notNull()
      .default(sql`(datetime('now'))`),
  },
  (table) => [
    index("file_index_chunks_entry_idx").on(table.entryId),
    index("file_index_chunks_user_idx").on(table.userId),
  ]
);

export const conversationsRelations = relations(conversations, ({ many, one }) => ({
  messages: many(messages),
  toolCalls: many(toolCalls),
  summary: one(conversationSummaries),
  emailDrafts: many(emailDrafts),
  pendingActions: many(pendingActions),
}));

export const messagesRelations = relations(messages, ({ one, many }) => ({
  conversation: one(conversations, {
    fields: [messages.conversationId],
    references: [conversations.id],
  }),
  attachments: many(attachments),
  toolCalls: many(toolCalls),
  sources: many(messageSources),
}));

export const toolCallsRelations = relations(toolCalls, ({ one, many }) => ({
  conversation: one(conversations, {
    fields: [toolCalls.conversationId],
    references: [conversations.id],
  }),
  message: one(messages, {
    fields: [toolCalls.messageId],
    references: [messages.id],
  }),
  sources: many(messageSources),
}));

export const attachmentsRelations = relations(attachments, ({ one, many }) => ({
  conversation: one(conversations, {
    fields: [attachments.conversationId],
    references: [conversations.id],
  }),
  message: one(messages, {
    fields: [attachments.messageId],
    references: [messages.id],
  }),
  chunks: many(documentChunks),
}));

export const documentChunksRelations = relations(documentChunks, ({ one }) => ({
  attachment: one(attachments, {
    fields: [documentChunks.attachmentId],
    references: [attachments.id],
  }),
}));

export const messageSourcesRelations = relations(messageSources, ({ one }) => ({
  message: one(messages, {
    fields: [messageSources.messageId],
    references: [messages.id],
  }),
  toolCall: one(toolCalls, {
    fields: [messageSources.toolCallId],
    references: [toolCalls.id],
  }),
}));

export const emailDraftsRelations = relations(emailDrafts, ({ one, many }) => ({
  conversation: one(conversations, {
    fields: [emailDrafts.conversationId],
    references: [conversations.id],
  }),
  pendingActions: many(pendingActions),
}));

export const pendingActionsRelations = relations(pendingActions, ({ one }) => ({
  conversation: one(conversations, {
    fields: [pendingActions.conversationId],
    references: [conversations.id],
  }),
  draft: one(emailDrafts, {
    fields: [pendingActions.draftId],
    references: [emailDrafts.id],
  }),
}));

export type Conversation = typeof conversations.$inferSelect;
export type Message = typeof messages.$inferSelect;
export type Attachment = typeof attachments.$inferSelect;
export type DocumentChunk = typeof documentChunks.$inferSelect;
export type Memory = typeof memories.$inferSelect;
export type ToolCall = typeof toolCalls.$inferSelect;
export type MessageSource = typeof messageSources.$inferSelect;
export type AgentRun = typeof agentRuns.$inferSelect;
export type OauthAccount = typeof oauthAccounts.$inferSelect;
export type AppSession = typeof appSessions.$inferSelect;
export type EmailDraft = typeof emailDrafts.$inferSelect;
export type PendingAction = typeof pendingActions.$inferSelect;
export type ActionAuditLogEntry = typeof actionAuditLog.$inferSelect;
