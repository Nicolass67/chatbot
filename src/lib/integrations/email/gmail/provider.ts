import type { gmail_v1 } from "googleapis";
import { createGmailApiClient } from "./client";
import {
  buildGmailListQuery,
  buildGmailRawMessage,
  normalizeGmailMessage,
  normalizeGmailThread,
} from "./normalizer";
import type {
  EmailProvider,
  ListMessagesParams,
  NormalizedDraft,
  NormalizedDraftInput,
  NormalizedEmailMessage,
  NormalizedEmailThread,
  ProviderCapabilities,
  SearchMessagesParams,
  SendDraftResult,
} from "../types";
import { EmailProviderError } from "../types";

const CAPABILITIES: ProviderCapabilities = {
  provider: "gmail",
  threads: true,
  drafts: true,
  search: true,
  send: true,
  trash: true,
  attachments: true,
  markRead: true,
};

export class GmailProvider implements EmailProvider {
  readonly capabilities = CAPABILITIES;

  constructor(
    private readonly accessToken: string,
    readonly accountEmail: string
  ) {}

  private get client() {
    return createGmailApiClient(this.accessToken);
  }

  private async fetchMessageSummaries(
    listResponse: gmail_v1.Schema$ListMessagesResponse
  ): Promise<NormalizedEmailMessage[]> {
    const ids = (listResponse.messages ?? [])
      .map((m) => m.id)
      .filter((id): id is string => Boolean(id));

    if (ids.length === 0) return [];

    const messages = await Promise.all(ids.map((id) => this.getMessage(id)));
    return messages;
  }

  async listMessages(
    params: ListMessagesParams
  ): Promise<NormalizedEmailMessage[]> {
    const q = buildGmailListQuery({
      query: params.query,
      after: params.after,
    });

    const response = await this.client.users.messages.list({
      userId: "me",
      q,
      maxResults: params.maxResults ?? 20,
      labelIds: params.labelIds,
    });

    return this.fetchMessageSummaries(response.data);
  }

  async getMessage(messageId: string): Promise<NormalizedEmailMessage> {
    try {
      const response = await this.client.users.messages.get({
        userId: "me",
        id: messageId,
        format: "full",
      });
      if (!response.data.id) {
        throw new EmailProviderError("NOT_FOUND", "Message introuvable.");
      }
      return normalizeGmailMessage(response.data);
    } catch (error) {
      if (error instanceof EmailProviderError) throw error;
      throw new EmailProviderError(
        "PROVIDER_ERROR",
        error instanceof Error ? error.message : "Erreur Gmail getMessage."
      );
    }
  }

  async getThread(threadId: string): Promise<NormalizedEmailThread> {
    try {
      const response = await this.client.users.threads.get({
        userId: "me",
        id: threadId,
        format: "full",
      });
      if (!response.data.id) {
        throw new EmailProviderError("NOT_FOUND", "Thread introuvable.");
      }
      return normalizeGmailThread(response.data);
    } catch (error) {
      if (error instanceof EmailProviderError) throw error;
      throw new EmailProviderError(
        "PROVIDER_ERROR",
        error instanceof Error ? error.message : "Erreur Gmail getThread."
      );
    }
  }

  async search(
    params: SearchMessagesParams
  ): Promise<NormalizedEmailMessage[]> {
    return this.listMessages({
      query: params.query,
      maxResults: params.maxResults ?? 20,
    });
  }

  async createDraft(input: NormalizedDraftInput): Promise<NormalizedDraft> {
    try {
      const raw = buildGmailRawMessage({
        to: input.to,
        cc: input.cc,
        bcc: input.bcc,
        subject: input.subject,
        bodyText: input.bodyText,
        inReplyToHeader: input.inReplyToHeader,
        referencesHeader: input.referencesHeader,
        attachments: input.attachments,
      });

      const response = await this.client.users.drafts.create({
        userId: "me",
        requestBody: {
          message: {
            raw,
            threadId: input.threadId,
          },
        },
      });

      const draft = response.data;
      const providerDraftId = draft.id;
      if (!providerDraftId) {
        throw new EmailProviderError(
          "PROVIDER_ERROR",
          "Gmail n'a pas retourné d'identifiant de brouillon."
        );
      }

      return {
        providerDraftId,
        threadId: draft.message?.threadId ?? input.threadId,
        messageId: draft.message?.id ?? undefined,
        to: input.to,
        cc: input.cc ?? [],
        bcc: input.bcc ?? [],
        subject: input.subject,
        bodyText: input.bodyText,
      };
    } catch (error) {
      if (error instanceof EmailProviderError) throw error;
      throw new EmailProviderError(
        "PROVIDER_ERROR",
        error instanceof Error ? error.message : "Erreur Gmail createDraft."
      );
    }
  }

  async sendDraft(providerDraftId: string): Promise<SendDraftResult> {
    try {
      const response = await this.client.users.drafts.send({
        userId: "me",
        requestBody: { id: providerDraftId },
      });

      const messageId = response.data.id;
      const threadId = response.data.threadId;
      if (!messageId || !threadId) {
        throw new EmailProviderError(
          "PROVIDER_ERROR",
          "Réponse Gmail incomplète après envoi."
        );
      }

      return { messageId, threadId };
    } catch (error) {
      if (error instanceof EmailProviderError) throw error;
      throw new EmailProviderError(
        "PROVIDER_ERROR",
        error instanceof Error ? error.message : "Erreur Gmail sendDraft."
      );
    }
  }

  async trashMessage(messageId: string): Promise<void> {
    try {
      await this.client.users.messages.trash({
        userId: "me",
        id: messageId,
      });
    } catch (error) {
      if (error instanceof EmailProviderError) throw error;
      throw new EmailProviderError(
        "PROVIDER_ERROR",
        error instanceof Error ? error.message : "Erreur Gmail trashMessage."
      );
    }
  }

  async markMessageRead(messageId: string): Promise<void> {
    try {
      await this.client.users.messages.modify({
        userId: "me",
        id: messageId,
        requestBody: {
          removeLabelIds: ["UNREAD"],
        },
      });
    } catch (error) {
      if (error instanceof EmailProviderError) throw error;
      throw new EmailProviderError(
        "PROVIDER_ERROR",
        error instanceof Error ? error.message : "Erreur Gmail markMessageRead."
      );
    }
  }

  async getAttachment(
    messageId: string,
    attachmentId: string
  ): Promise<{ data: Buffer; size: number }> {
    try {
      const response = await this.client.users.messages.attachments.get({
        userId: "me",
        messageId,
        id: attachmentId,
      });
      const raw = response.data.data;
      if (!raw) {
        throw new EmailProviderError(
          "PROVIDER_ERROR",
          "Pièce jointe Gmail vide."
        );
      }
      const data = Buffer.from(
        raw.replace(/-/g, "+").replace(/_/g, "/"),
        "base64"
      );
      return { data, size: response.data.size ?? data.length };
    } catch (error) {
      if (error instanceof EmailProviderError) throw error;
      throw new EmailProviderError(
        "PROVIDER_ERROR",
        error instanceof Error
          ? error.message
          : "Erreur Gmail getAttachment."
      );
    }
  }
}
