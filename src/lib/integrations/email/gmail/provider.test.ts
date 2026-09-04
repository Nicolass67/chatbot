import { beforeEach, describe, expect, it, vi } from "vitest";
import { GmailProvider } from "./provider";

const mockMessagesList = vi.fn();
const mockMessagesGet = vi.fn();
const mockThreadsGet = vi.fn();
const mockDraftsCreate = vi.fn();
const mockDraftsSend = vi.fn();
const mockMessagesTrash = vi.fn();

vi.mock("./client", () => ({
  createGmailApiClient: () => ({
    users: {
      messages: {
        list: mockMessagesList,
        get: mockMessagesGet,
        trash: mockMessagesTrash,
        attachments: {
          get: vi.fn(),
        },
      },
      threads: {
        get: mockThreadsGet,
      },
      drafts: {
        create: mockDraftsCreate,
        send: mockDraftsSend,
      },
    },
  }),
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

describe("GmailProvider", () => {
  let provider: GmailProvider;

  beforeEach(() => {
    vi.clearAllMocks();
    provider = new GmailProvider("access-token", "me@gmail.com");
  });

  it("expose les capabilities Gmail", () => {
    expect(provider.capabilities).toEqual({
      provider: "gmail",
      threads: true,
      drafts: true,
      search: true,
      send: true,
      trash: true,
      attachments: true,
      markRead: true,
    });
    expect(provider.accountEmail).toBe("me@gmail.com");
  });

  it("listMessages récupère les résumés (metadata)", async () => {
    mockMessagesList.mockResolvedValue({
      data: { messages: [{ id: "msg-1" }] },
    });
    mockMessagesGet.mockResolvedValue({
      data: {
        id: "msg-1",
        threadId: "thread-1",
        snippet: "Hello",
        labelIds: ["INBOX", "UNREAD"],
        payload: {
          headers: [
            { name: "From", value: "a@example.com" },
            { name: "Subject", value: "Hi" },
          ],
        },
      },
    });

    const messages = await provider.listMessages({ maxResults: 5 });

    expect(mockMessagesList).toHaveBeenCalledWith({
      userId: "me",
      q: undefined,
      maxResults: 5,
      labelIds: undefined,
      pageToken: undefined,
    });
    expect(mockMessagesGet).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: "me",
        id: "msg-1",
        format: "metadata",
      })
    );
    expect(messages).toHaveLength(1);
    expect(messages[0]?.id).toBe("msg-1");
    expect(messages[0]?.subject).toBe("Hi");
    expect(messages[0]?.isUnread).toBe(true);
  });

  it("search délègue à listMessages avec query", async () => {
    mockMessagesList.mockResolvedValue({ data: { messages: [] } });

    await provider.search({ query: "is:unread", maxResults: 10 });

    expect(mockMessagesList).toHaveBeenCalledWith({
      userId: "me",
      q: "is:unread",
      maxResults: 10,
      labelIds: undefined,
      pageToken: undefined,
    });
  });

  it("getThread normalise le fil", async () => {
    mockThreadsGet.mockResolvedValue({
      data: {
        id: "thread-1",
        messages: [
          {
            id: "m1",
            threadId: "thread-1",
            payload: {
              headers: [
                { name: "From", value: "a@example.com" },
                { name: "Subject", value: "Thread" },
              ],
            },
          },
        ],
      },
    });

    const thread = await provider.getThread("thread-1");
    expect(thread.id).toBe("thread-1");
    expect(thread.messages).toHaveLength(1);
  });

  it("createDraft envoie un message raw à Gmail", async () => {
    mockDraftsCreate.mockResolvedValue({
      data: {
        id: "draft-1",
        message: { id: "msg-draft", threadId: "thread-2" },
      },
    });

    const draft = await provider.createDraft({
      to: ["dest@example.com"],
      subject: "Objet",
      bodyText: "Corps",
      threadId: "thread-2",
    });

    expect(mockDraftsCreate).toHaveBeenCalledOnce();
    expect(draft.providerDraftId).toBe("draft-1");
    expect(draft.threadId).toBe("thread-2");
    expect(draft.to).toEqual(["dest@example.com"]);
  });

  it("sendDraft retourne messageId et threadId", async () => {
    mockDraftsSend.mockResolvedValue({
      data: { id: "sent-msg", threadId: "thread-3" },
    });

    const result = await provider.sendDraft("draft-99");

    expect(mockDraftsSend).toHaveBeenCalledWith({
      userId: "me",
      requestBody: { id: "draft-99" },
    });
    expect(result).toEqual({
      messageId: "sent-msg",
      threadId: "thread-3",
    });
  });

  it("trashMessage déplace un message à la corbeille", async () => {
    mockMessagesTrash.mockResolvedValue({ data: {} });
    await provider.trashMessage("msg-trash-1");
    expect(mockMessagesTrash).toHaveBeenCalledWith({
      userId: "me",
      id: "msg-trash-1",
    });
  });
});
