import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ChatScreen: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(AppNavigation.self) private var nav
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    let conversation: ConversationDTO
    var onOpenHistory: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    /// Scope forcé (Assistant Mail/Files). Nil = Chat général.
    var forcedScope: ConversationScope? = nil
    var forcedActiveContext: ActiveContextHint? = nil

    @State private var messages: [MessageDTO] = []
    @State private var draft = ""
    @State private var streamingText = ""
    @State private var thinkingKind: ThinkingKind?
    @State private var isSending = false
    @State private var error: String?
    @State private var sendTask: Task<Void, Never>?
    @State private var pendingAttachments: [UploadedAttachment] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var chatMode: String = "chat"
    @State private var webSearchEnabled = false
    @State private var editingMessageId: String?
    @State private var lightbox: LightboxItem?
    @State private var conversationTitle: String = ""
    @State private var showDocImporter = false
    @State private var showTools = false
    @State private var quickLookURL: IdentifiedURL?
    @State private var streamInterrupted = false
    @State private var canRetrySend = false

    @State private var models: [ModelOptionDTO] = []
    @State private var selectedModel: String = ""
    @State private var reasoningModes: [ReasoningModeDTO] = []
    @State private var reasoningEffort: String = ""
    @State private var modelSwitching = false

    @State private var streamSources: [SearchSourceDTO] = []
    @State private var streamMailHandoff: MailHandoffDTO?
    @State private var streamFilesHandoff: FilesHandoffDTO?
    @State private var streamFilesFound: [FilesFoundFileDTO] = []
    @State private var draftCardId: String?
    @State private var draftCardText = ""
    @State private var draftCardTo = ""
    @State private var draftCardSubject = ""
    @State private var draftCardStatus = "Brouillon"
    @State private var draftCardCandidates: [String] = []
    @State private var draftCardEditing = false
    @State private var draftCardBusy = false
    @State private var draftCardStreaming = false
    @State private var draftInConversation = false
    @State private var lastSources: [SearchSourceDTO] = []
    @State private var lastMailHandoff: MailHandoffDTO?
    @State private var lastFilesHandoff: FilesHandoffDTO?
    @State private var lastFilesFound: [FilesFoundFileDTO] = []
    @State private var agentActivity = AgentActivityState()
    @State private var runtimeStatus: String = "…"
    @State private var showScrollDown = false
    /// Distance au bas en dessous de laquelle le bouton « revenir en bas » est inutile.
    private let scrollBottomProximityThreshold: CGFloat = 120
    @State private var scrollToken = 0
    @State private var memoryNotice: String?
    @State private var pendingFileAction: PendingFileAction?
    @State private var confirmingFileAction = false
    @State private var chromeById: [String: MessageChromeMeta] = [:]
    @State private var streamingAssistantId: String?
    @State private var contextSnapshot: ContextSnapshotDTO?
    @State private var streamingService = ChatStreamingService()
    /// Quand draft/files_found = résultat principal : ne pas promouvoir la narration textuelle.
    @State private var suppressAssistantNarration = false
    @State private var exportShareURL: IdentifiedURL?
    @State private var settingsHydrated = false

    struct PendingFileAction: Identifiable, Equatable {
        let id: String
        let confirmationToken: String
        let op: String
        let detail: String
        let expiresAt: String?
    }

    struct IdentifiedURL: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
    }

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 0) {
                if let scope = forcedScope, scope == .mail {
                    PersistentProductActionsBar(
                        scope: scope,
                        hasMailThread: forcedActiveContext?.mailThreadId != nil,
                        hasDraft: draftCardId != nil,
                        onAction: { action in
                            Task { await runQuickAction(action) }
                        }
                    )
                }
                messageScroll
                if shouldShowAgentStrip {
                    AgentActivityView(state: agentActivity)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if let thinkingKind, isSending {
                    ThinkingStatusView(kind: thinkingKind)
                        .transition(.opacity)
                }
                if let pendingFileAction {
                    FileActionPendingCard(
                        op: pendingFileAction.op,
                        detail: pendingFileAction.detail,
                        expiresAt: pendingFileAction.expiresAt,
                        confirming: confirmingFileAction,
                        onConfirm: { Task { await resolveFileAction(confirm: true) } },
                        onCancel: { Task { await resolveFileAction(confirm: false) } }
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                }
                if let memoryNotice {
                    MemorySavedNotice(text: memoryNotice) {
                        self.memoryNotice = nil
                        nav.openMemory()
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                }
                if let error {
                    SoftErrorBanner(message: error, retryTitle: canRetrySend ? "Réessayer" : "OK") {
                        if canRetrySend {
                            canRetrySend = false
                            self.error = nil
                            sendTask = Task { await send(options: ChatSendOptions(regenerate: true, mode: chatMode)) }
                        } else {
                            self.error = nil
                        }
                    }
                    .padding(.horizontal, AppTheme.space16)
                    .padding(.vertical, AppTheme.space8)
                }
                HStack {
                    RuntimeStatusPill(status: displayRuntimeStatus)
                    Spacer(minLength: 0)
                    if !assistantReadyForSend {
                        Text(sendBlockedHint)
                            .font(CNFont.caption2)
                            .foregroundStyle(AppTheme.mutedForeground)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, AppTheme.space16)
                .padding(.bottom, 2)
                composer
            }
        }
        .navigationTitle(
            forcedScope != nil
                ? ""
                : (conversationTitle.isEmpty ? "Nouvelle conversation" : conversationTitle)
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if forcedScope == nil {
                ToolbarItem(placement: .topBarLeading) {
                    if let onOpenHistory {
                        Button(action: onOpenHistory) {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Conversations")
                        .accessibilityIdentifier(A11yID.Chat.history)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let onOpenSettings {
                        Button(action: onOpenSettings) {
                            Image(systemName: "person.crop.circle")
                        }
                        .accessibilityLabel("Réglages")
                        .accessibilityIdentifier(A11yID.Chat.settings)
                    }
                }
            }
        }
        .task {
            conversationTitle = conversation.title ?? ""
            chatMode = conversation.chatMode ?? "chat"
            reasoningEffort = conversation.reasoningEffort ?? ""
            chromeById = ConversationSessionStore.chrome(for: conversation.id)
            persistActiveConversation()
            await loadMessages()
            await loadSettings()
            await refreshRuntimeStatus()
        }
        .task {
            // Observation périodique de l’état réel (pas une source de vérité arbitraire).
            while !Task.isCancelled {
                await refreshRuntimeStatus()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        .onChange(of: nav.chatComposerPrefill) { _, text in
            guard let text, !text.isEmpty else { return }
            draft = text
            nav.chatComposerPrefill = nil
            AppHaptics.light()
        }
        .onAppear {
            if let text = nav.chatComposerPrefill, !text.isEmpty {
                draft = text
                nav.chatComposerPrefill = nil
            }
            // Retour depuis Files / preview : recharger si l’état local a été vidé.
            if messages.isEmpty, !isSending {
                chromeById = ConversationSessionStore.chrome(for: conversation.id)
                Task { await loadMessages() }
            }
        }
        // Ne pas annuler le stream sur changement d’onglet / preview fichier —
        // seul le background (scenePhase) ou Stop explicite interrompt.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, isSending {
                sendTask?.cancel()
                Task { await streamingService.cancel() }
                streamInterrupted = true
                isSending = false
                thinkingKind = nil
                agentActivity = AgentActivityState()
                if !streamingText.isEmpty {
                    messages.append(
                        MessageDTO(
                            id: "partial-\(UUID().uuidString)",
                            role: "assistant",
                            content: streamingText + "\n\n_(Interrompu — app en arrière-plan)_",
                            createdAt: nil
                        )
                    )
                    streamingText = ""
                }
            } else if phase == .active, streamInterrupted {
                streamInterrupted = false
                Task {
                    await loadMessages()
                    runtimeStatus = (try? await client.runtimeStatus()) ?? runtimeStatus
                }
            }
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await handlePickedPhoto(newItem) }
        }
        .fullScreenCover(item: $lightbox) { item in
            ImageLightboxView(item: item) { lightbox = nil }
        }
        .sheet(item: $quickLookURL) { item in
            NavigationStack {
                QuickLookPreview(url: item.url) {
                    quickLookURL = nil
                }
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { quickLookURL = nil }
                    }
                }
            }
            .presentationDetents([.large])
        }
        .sheet(item: $exportShareURL) { item in
            NavigationStack {
                ShareLink(item: item.url) {
                    Label("Partager « \(item.title) »", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding()
                .navigationTitle("Télécharger")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") { exportShareURL = nil }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .fileImporter(
            isPresented: $showDocImporter,
            allowedContentTypes: [.pdf, .plainText, .utf8PlainText, .data, .image],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImportedDoc(result) }
        }
    }

    private var messageScroll: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if messages.isEmpty && streamingText.isEmpty {
                            emptyThread
                        }
                        ForEach(messages) { msg in
                            let chrome = chromeById[msg.id] ?? MessageChromeMeta()
                            MessageBubble(
                                message: msg,
                                token: session.token,
                                baseURL: session.baseURL,
                                isEditing: editingMessageId == msg.id,
                                sources: chrome.sources,
                                mailHandoff: chrome.mailHandoff,
                                filesHandoff: chrome.filesHandoff,
                                filesFound: chrome.filesFound,
                                onCopy: {
                                    UIPasteboard.general.string = msg.content
                                    AppHaptics.light()
                                },
                                onEdit: { beginEdit(msg) },
                                onRegenerate: { Task { await regenerate() } },
                                onOpenImage: { lightbox = $0 },
                                onMailHandoff: {
                                    nav.openMail(
                                        threadId: chrome.mailHandoff?.threadId,
                                        query: chrome.mailHandoff?.query,
                                        label: chrome.mailHandoff?.label
                                    )
                                },
                                onFilesHandoff: {
                                    nav.openFiles(
                                        rootId: chrome.filesHandoff?.rootId,
                                        query: chrome.filesHandoff?.query
                                    )
                                },
                                onOpenDocument: { url, title in
                                    quickLookURL = IdentifiedURL(url: url, title: title)
                                },
                                onOpenFoundFile: { file in
                                    openFoundFilePreview(file)
                                },
                                onDownloadFoundFile: { file in
                                    Task { await downloadFoundFile(file) }
                                },
                                onRevealFoundFile: { file in
                                    revealFoundFileFolder(file)
                                }
                            )
                            .id(msg.id)
                        }
                        if !streamingText.isEmpty && streamingAssistantId == nil {
                            MessageBubble(
                                message: MessageDTO(
                                    id: "streaming",
                                    role: "assistant",
                                    content: streamingText,
                                    createdAt: nil
                                ),
                                token: session.token,
                                baseURL: session.baseURL,
                                isEditing: false,
                                sources: streamSources,
                                mailHandoff: streamMailHandoff,
                                filesHandoff: streamFilesHandoff,
                                filesFound: streamFilesFound,
                                onCopy: {},
                                onEdit: {},
                                onRegenerate: {},
                                onOpenImage: { lightbox = $0 },
                                onMailHandoff: {
                                    nav.openMail(
                                        threadId: streamMailHandoff?.threadId,
                                        query: streamMailHandoff?.query,
                                        label: streamMailHandoff?.label
                                    )
                                },
                                onFilesHandoff: {
                                    nav.openFiles(
                                        rootId: streamFilesHandoff?.rootId,
                                        query: streamFilesHandoff?.query
                                    )
                                },
                                onOpenDocument: { url, title in
                                    quickLookURL = IdentifiedURL(url: url, title: title)
                                },
                                onOpenFoundFile: { file in
                                    openFoundFilePreview(file)
                                },
                                onDownloadFoundFile: { file in
                                    Task { await downloadFoundFile(file) }
                                },
                                onRevealFoundFile: { file in
                                    revealFoundFileFolder(file)
                                }
                            )
                            .id("streaming")
                        } else if streamingText.isEmpty && !streamFilesFound.isEmpty && streamingAssistantId == nil {
                            MessageBubble(
                                message: MessageDTO(
                                    id: "streaming",
                                    role: "assistant",
                                    content: "",
                                    createdAt: nil
                                ),
                                token: session.token,
                                baseURL: session.baseURL,
                                isEditing: false,
                                filesFound: streamFilesFound,
                                onCopy: {},
                                onEdit: {},
                                onRegenerate: {},
                                onOpenImage: { _ in },
                                onOpenFoundFile: { file in
                                    openFoundFilePreview(file)
                                },
                                onDownloadFoundFile: { file in
                                    Task { await downloadFoundFile(file) }
                                },
                                onRevealFoundFile: { file in
                                    revealFoundFileFolder(file)
                                }
                            )
                            .id("streaming-files")
                        }
                        if draftInConversation || draftCardId != nil || draftCardStreaming {
                            MailDraftProposal(
                                draftText: $draftCardText,
                                draftId: draftCardId,
                                toLabel: draftCardTo.isEmpty ? "" : "À : \(draftCardTo)",
                                subjectLabel: draftCardSubject.isEmpty ? "" : "Objet : \(draftCardSubject)",
                                statusLabel: draftCardStatus,
                                isEditing: draftCardEditing,
                                busy: draftCardBusy,
                                isStreaming: draftCardStreaming,
                                candidates: draftCardCandidates,
                                onSelectCandidate: { email in
                                    draftCardTo = email
                                    draftCardCandidates = []
                                    Task { await applyDraftRecipient(email) }
                                },
                                onEditToggle: { draftCardEditing.toggle() },
                                onRetry: {
                                    Task { await send(forcedText: "Réécris le brouillon de façon plus claire.", hideUserMessage: true) }
                                },
                                onSend: {
                                    Task { await sendDraftCard() }
                                },
                                onAttach: {
                                    showDocImporter = true
                                }
                            )
                            .id("conversation-draft")
                        }
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    let contentH = geometry.contentSize.height
                    let visibleH = geometry.containerSize.height
                    let offsetY = geometry.contentOffset.y
                    let bottomInset = geometry.contentInsets.bottom
                    return max(0, contentH + bottomInset - visibleH - offsetY)
                } action: { _, distanceToBottom in
                    let shouldShow = distanceToBottom > scrollBottomProximityThreshold
                    if showScrollDown != shouldShow {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showScrollDown = shouldShow
                        }
                    }
                }
                .onChange(of: streamingText) { _, text in
                    guard !showScrollDown, !text.isEmpty else { return }
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: messages.count) { _, _ in
                    guard !showScrollDown else { return }
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: scrollToken) { _, _ in
                    showScrollDown = false
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: draftCardText) { _, _ in
                    guard draftInConversation || draftCardStreaming else { return }
                    proxy.scrollTo("conversation-draft", anchor: .bottom)
                }
            }

            if showScrollDown {
                ScrollToBottomButton {
                    AppHaptics.light()
                    scrollToken += 1
                }
                .padding(.trailing, 14)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .scale))
            }
        }
    }

    @ViewBuilder
    private var emptyThread: some View {
        if let scope = forcedScope {
            ContextualQuickActions(
                scope: scope,
                hasMailThread: forcedActiveContext?.mailThreadId != nil,
                onAction: { action in
                    Task { await runQuickAction(action) }
                }
            )
        } else {
            EmptyChatCanvas { suggestion in
                draft = suggestion
            }
        }
    }

    enum QuickAction: String {
        case summarize, reply, draft, extractTasks, searchUnread, improve
    }

    private func runQuickAction(_ action: QuickAction) async {
        draft = ""
        // Draft card visible : actions ciblées (pas de prompts doubles).
        if draftCardId != nil {
            switch action {
            case .improve:
                await send(
                    forcedText: "Améliore le brouillon en cours via les outils mail (sans narrer le contenu).",
                    hideUserMessage: true
                )
                return
            case .extractTasks:
                showDocImporter = true
                return
            case .searchUnread:
                await sendDraftCard()
                return
            default:
                break
            }
        }
        // Actions produit : jamais injectées comme messages user visibles.
        if let threadId = forcedActiveContext?.mailThreadId {
            switch action {
            case .summarize:
                await runMailSummarizeProduct(threadId: threadId)
                return
            case .reply:
                await runMailReplyProduct(threadId: threadId)
                return
            default:
                break
            }
        }
        let prompt: String
        switch action {
        case .summarize:
            prompt = "Résume ce mail de façon claire et concise."
        case .reply:
            prompt = "Prépare une réponse professionnelle à ce mail et crée un brouillon via l’outil email_create_draft (sans narrer le brouillon)."
        case .draft:
            prompt = "Crée un nouveau brouillon d’email pour ce contexte via email_create_draft."
        case .extractTasks:
            prompt = "Extrais les tâches et dates demandées dans ce mail."
        case .searchUnread:
            prompt = forcedScope == .mail
                ? "Résume mes mails non lus les plus importants."
                : "Liste les fichiers pertinents pour mon contexte actuel."
        case .improve:
            prompt = "Améliore le brouillon en cours pour le rendre plus clair et professionnel via les outils mail."
        }
        await send(forcedText: prompt, hideUserMessage: true)
    }

    private func runMailSummarizeProduct(threadId: String) async {
        guard !isSending else { return }
        isSending = true
        error = nil
        thinkingKind = .custom("Analyse du message…")
        let summaryId = "mail-summary-\(UUID().uuidString)"
        messages.append(MessageDTO(id: summaryId, role: "assistant", content: "", createdAt: nil))
        defer {
            isSending = false
            thinkingKind = nil
        }
        do {
            try await client.streamSummarizeMail(threadId: threadId) { token in
                Task { @MainActor in
                    if self.thinkingKind != nil { self.thinkingKind = nil }
                    if let idx = self.messages.firstIndex(where: { $0.id == summaryId }) {
                        let prev = self.messages[idx]
                        self.messages[idx] = MessageDTO(
                            id: prev.id,
                            role: prev.role,
                            content: prev.content + token,
                            createdAt: prev.createdAt,
                            attachments: prev.attachments
                        )
                    }
                }
            }
            AppHaptics.success()
            scrollToken += 1
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == summaryId }),
               messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.remove(at: idx)
            }
            self.error = error.localizedDescription
        }
    }

    private func runMailReplyProduct(threadId: String) async {
        guard !isSending else { return }
        isSending = true
        error = nil
        thinkingKind = .custom("Préparation de la réponse…")
        draftInConversation = true
        draftCardStreaming = true
        draftCardStatus = "Rédaction…"
        draftCardText = ""
        draftCardEditing = false
        defer {
            isSending = false
            thinkingKind = nil
            draftCardStreaming = false
            draftCardStatus = "Brouillon"
        }
        do {
            let result = try await client.streamSuggestMailReply(threadId: threadId) { token in
                Task { @MainActor in
                    if self.thinkingKind != nil { self.thinkingKind = nil }
                    self.draftCardText += token
                }
            }
            if let id = result.draftId, !id.isEmpty {
                draftCardId = id
            }
            if !result.bodyText.isEmpty {
                draftCardText = result.bodyText
            }
            draftCardTo = result.to.joined(separator: ", ")
            draftCardSubject = result.subject ?? ""
            draftInConversation = true
            AppHaptics.success()
            scrollToken += 1
        } catch {
            draftInConversation = draftCardId != nil
            self.error = error.localizedDescription
        }
    }

    private func applyDraftRecipient(_ email: String) async {
        guard let draftId = draftCardId else { return }
        do {
            try await client.updateEmailDraft(id: draftId, bodyText: draftCardText, to: [email])
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func persistActiveConversation() {
        let scope = forcedScope ?? .general
        let key: String? = {
            if scope == .general { return nil }
            return forcedActiveContext?.mailThreadId
                ?? forcedActiveContext?.fileId
                ?? ConversationSessionStore.globalContextKey
        }()
        ConversationSessionStore.save(
            conversationId: conversation.id,
            scope: scope,
            contextKey: key
        )
    }

    private func openFoundFilePreview(_ file: FilesFoundFileDTO) {
        persistActiveConversation()
        // Mail sheet uniquement : fermer pour révéler l’onglet Files.
        // Chat général : conserver l’écran (TabView) pour retrouver la conversation.
        if forcedScope == .mail { dismiss() }
        let parent = FilesPathHelpers.parentFolder(of: file.relativePath)
        nav.openFilePreview(
            fileId: file.id,
            fileName: file.filename,
            rootId: file.rootId,
            folderPath: parent
        )
    }

    private func revealFoundFileFolder(_ file: FilesFoundFileDTO) {
        persistActiveConversation()
        if forcedScope == .mail { dismiss() }
        let parent = FilesPathHelpers.parentFolder(of: file.relativePath)
        nav.openFileFolder(
            rootId: file.rootId,
            folderPath: parent,
            title: FilesPathHelpers.lastSegment(of: parent).isEmpty
                ? nil
                : FilesPathHelpers.lastSegment(of: parent)
        )
    }

    private func downloadFoundFile(_ file: FilesFoundFileDTO) async {
        do {
            let content = try await client.fetchFileContent(fileId: file.id)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(file.filename)
            if let binary = content.binary {
                try binary.write(to: tmp, options: .atomic)
            } else if let text = content.text {
                try Data(text.utf8).write(to: tmp, options: .atomic)
            } else {
                throw APIClientError.decode
            }
            exportShareURL = IdentifiedURL(url: tmp, title: file.filename)
            AppHaptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendDraftCard() async {
        guard let draftId = draftCardId else { return }
        draftCardBusy = true
        defer { draftCardBusy = false }
        do {
            let body = draftCardText.trimmingCharacters(in: .whitespacesAndNewlines)
            try await client.updateEmailDraft(id: draftId, bodyText: body)
            try await client.validateEmailDraft(id: draftId)
            let proposal = try await client.proposeEmailSend(draftId: draftId)
            try await client.confirmEmailSend(
                actionId: proposal.actionId,
                confirmationToken: proposal.confirmationToken,
                conversationId: conversation.id
            )
            draftCardId = nil
            draftCardText = ""
            draftCardTo = ""
            draftCardSubject = ""
            draftCardCandidates = []
            draftInConversation = false
            AppHaptics.success()
        } catch {
            self.error = error.localizedDescription
            AppHaptics.warning()
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(pendingAttachments) { att in
                            PendingAttachmentCard(attachment: att) {
                                Task { await removePending(att) }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                }
            }

            ComposerCapsule(
                draft: $draft,
                photoItem: $photoItem,
                showTools: $showTools,
                placeholder: editingMessageId == nil ? "Message" : "Modifier le message…",
                canSend: canSend,
                isSending: isSending,
                uploading: uploading,
                editing: editingMessageId != nil,
                chatMode: chatMode,
                webSearchEnabled: webSearchEnabled,
                selectedModelName: selectedModel,
                reasoningModes: reasoningModes,
                reasoningEffort: reasoningEffort,
                models: models,
                modelSwitching: modelSwitching,
                onModeChange: { mode in applyMode(mode) },
                onWebChange: { enabled in applyWeb(enabled) },
                onModelChange: { modelId in Task { await applyModel(modelId) } },
                onReasoningChange: { mode in applyReasoning(mode) },
                onSend: {
                    sendTask = Task { await send() }
                },
                onStop: {
                    sendTask?.cancel()
                    sendTask = nil
                    Task { await streamingService.cancel() }
                    finalizeStoppedStream()
                },
                onPickDoc: { showDocImporter = true },
                onCancelEdit: {
                    editingMessageId = nil
                    draft = ""
                }
            )
            .padding(.horizontal, AppTheme.space12)
            .padding(.bottom, AppTheme.space12)
            .padding(.top, AppTheme.space4)
        }
    }

    private var canSend: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasContent = (hasText || !pendingAttachments.isEmpty) && !uploading && !pendingAttachments.contains(where: \.isUploading)
        return hasContent && assistantReadyForSend
    }

    private var assistantReadyForSend: Bool {
        switch runtimeStatus.uppercased() {
        case "READY", "BUSY":
            return !modelSwitching
        default:
            return false
        }
    }

    private var displayRuntimeStatus: String {
        if modelSwitching {
            return "SWITCHING"
        }
        return runtimeStatus
    }

    private var sendBlockedHint: String {
        switch displayRuntimeStatus.uppercased() {
        case "OFFLINE": return "Choisis un modèle"
        case "LOADING", "LOADING_MODEL", "SWITCHING": return "Patiente…"
        case "ERROR": return "Vérifie le modèle"
        default: return "Indisponible"
        }
    }

    private func refreshRuntimeStatus() async {
        guard !modelSwitching else { return }
        if let snap = try? await client.runtimeSnapshot() {
            applySnapshotToRuntime(snap)
        } else if let status = try? await client.runtimeStatus() {
            runtimeStatus = status
        }
    }

    private func applySnapshotToRuntime(_ snap: APIClient.RuntimeSnapshotDTO) {
        let phase = (snap.phase ?? "").lowercased()
        if phase == "ready", snap.loadedModel != nil {
            runtimeStatus = "READY"
            if let loaded = snap.loadedModel, !loaded.isEmpty, selectedModel.isEmpty {
                selectedModel = loaded
            }
        } else if phase == "loading" || phase == "unloading" {
            runtimeStatus = modelSwitching || snap.targetModel != nil ? "SWITCHING" : "LOADING_MODEL"
        } else if phase == "error" {
            runtimeStatus = "ERROR"
        } else if snap.loadedModel == nil {
            runtimeStatus = snap.status.uppercased() == "OFFLINE" ? "OFFLINE" : (snap.status.isEmpty ? "OFFLINE" : snap.status)
        } else {
            runtimeStatus = snap.status.isEmpty ? "UNKNOWN" : snap.status
        }
    }

    private func loadMessages(preserveAssistantId: String? = nil) async {
        do {
            let server = try await client.listMessages(conversationId: conversation.id)
            messages = mergeMessages(local: messages, server: server, preserveAssistantId: preserveAssistantId)
            if let preserveAssistantId {
                chromeById = ConversationSessionStore.remountChrome(
                    conversationId: conversation.id,
                    from: preserveAssistantId,
                    onto: messages
                )
            } else {
                let stored = ConversationSessionStore.chrome(for: conversation.id)
                if !stored.isEmpty {
                    chromeById = stored
                }
            }
            error = nil
            let ids = messages.flatMap { $0.attachments ?? [] }
                .filter { ($0.mimeType ?? "").hasPrefix("image/") || $0.type == "image" }
                .map(\.id)
            client.prefetchAttachmentThumbs(ids: ids, maxPixelSize: 360)
            contextSnapshot = try? await client.conversationContext(conversationId: conversation.id)
            scrollToken += 1
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Fusionne serveur + local pour éviter un frame vide pendant/après le stream.
    private func mergeMessages(
        local: [MessageDTO],
        server: [MessageDTO],
        preserveAssistantId: String?
    ) -> [MessageDTO] {
        if server.isEmpty { return local }
        var byId = Dictionary(uniqueKeysWithValues: server.map { ($0.id, $0) })
        // Conserver le contenu local plus long si le serveur est encore en retard
        for msg in local where msg.role == "assistant" {
            if let existing = byId[msg.id], existing.content.count < msg.content.count {
                byId[msg.id] = MessageDTO(
                    id: msg.id,
                    role: msg.role,
                    content: msg.content,
                    createdAt: existing.createdAt ?? msg.createdAt,
                    attachments: existing.attachments ?? msg.attachments
                )
            } else if byId[msg.id] == nil,
                      let preserveAssistantId,
                      msg.id == preserveAssistantId,
                      !msg.content.isEmpty {
                byId[msg.id] = msg
            }
        }
        // Ordre serveur ; append locaux orphelins (optimistic user / promote)
        var ordered = server.map { byId[$0.id]! }
        let serverIds = Set(server.map(\.id))
        for msg in local where !serverIds.contains(msg.id) {
            if msg.id.hasPrefix("local-") || msg.id.hasPrefix("partial-") { continue }
            if msg.id == preserveAssistantId || msg.id.hasPrefix("asst-") {
                if !ordered.contains(where: { $0.role == "assistant" && $0.content == msg.content }) {
                    ordered.append(msg)
                }
            }
        }
        return ordered
    }

    private func loadSettings() async {
        async let web = client.getWebSearchEnabled()
        async let settings = client.getSettings()
        async let modelList = client.listModels()
        let remoteWeb = (try? await web) ?? false
        let remoteModels = (try? await modelList) ?? []
        models = remoteModels
        // Ne pas écraser un toggle utilisateur déjà modifié pendant le load.
        if !settingsHydrated {
            webSearchEnabled = remoteWeb
        }
        if let s = try? await settings {
            if selectedModel.isEmpty || !modelSwitching {
                let remoteModel = (s["selectedModel"] as? String) ?? ""
                if !modelSwitching {
                    selectedModel = remoteModel
                }
            }
            if reasoningEffort.isEmpty {
                reasoningEffort = (s["defaultReasoningEffort"] as? String) ?? ""
            }
        }
        settingsHydrated = true
        await refreshReasoningCaps()
    }

    private func refreshReasoningCaps() async {
        guard !selectedModel.isEmpty else {
            reasoningModes = []
            return
        }
        if let caps = try? await client.reasoningCapabilities(modelId: selectedModel) {
            reasoningModes = caps.modes ?? []
            if reasoningEffort.isEmpty, let def = caps.defaultModeId {
                reasoningEffort = def
            }
        }
    }

    private func applyMode(_ next: String) {
        let previous = chatMode
        guard next != previous else { return }
        chatMode = next
        Task {
            do {
                try await client.patchConversationMode(id: conversation.id, mode: next)
            } catch {
                chatMode = previous
                self.error = error.localizedDescription
            }
        }
    }

    private func applyWeb(_ next: Bool) {
        let previous = webSearchEnabled
        guard next != previous else { return }
        webSearchEnabled = next
        Task {
            do {
                try await client.setWebSearchEnabled(next)
            } catch {
                webSearchEnabled = previous
                self.error = error.localizedDescription
            }
        }
    }

    private func applyModel(_ modelId: String) async {
        let previous = selectedModel
        guard modelId != previous || modelSwitching else { return }
        selectedModel = modelId

        // Snapshot avant POST — modèle déjà chargé → READY immédiat.
        if let snap = try? await client.runtimeSnapshot(),
           snap.phase == "ready",
           snap.loadedModel == modelId {
            modelSwitching = false
            runtimeStatus = "READY"
            await refreshReasoningCaps()
            return
        }

        modelSwitching = true
        runtimeStatus = "SWITCHING"
        do {
            let accepted = try await client.selectModel(modelId)
            if accepted.phase == "ready", accepted.loadedModel == modelId {
                modelSwitching = false
                runtimeStatus = "READY"
                await refreshReasoningCaps()
                return
            }
            // Observer l’état réel jusqu’à READY / ERROR (pas un timeout comme vérité).
            var sawReady = false
            var lastPhase: String?
            for _ in 0..<80 {
                if Task.isCancelled { break }
                if let snap = try? await client.runtimeSnapshot() {
                    lastPhase = snap.phase
                    applySnapshotToRuntime(snap)
                    if snap.phase == "ready", snap.loadedModel == modelId {
                        sawReady = true
                        runtimeStatus = "READY"
                        modelSwitching = false
                        await refreshReasoningCaps()
                        return
                    }
                    if snap.phase == "error" {
                        selectedModel = previous
                        error = snap.message ?? "Impossible de charger le modèle"
                        modelSwitching = false
                        runtimeStatus = snap.loadedModel != nil ? "READY" : "ERROR"
                        return
                    }
                    if snap.phase == "loading" || snap.phase == "unloading" {
                        runtimeStatus = "SWITCHING"
                    }
                }
                // Intervalle d’observation uniquement — ne décide pas de READY/ERROR.
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            // Dernière chance : si le modèle est prêt malgré la boucle, ne pas crier timeout.
            if let snap = try? await client.runtimeSnapshot() {
                if snap.phase == "ready", snap.loadedModel == modelId {
                    runtimeStatus = "READY"
                    modelSwitching = false
                    await refreshReasoningCaps()
                    return
                }
                if snap.loadedModel == modelId {
                    runtimeStatus = "READY"
                    modelSwitching = false
                    await refreshReasoningCaps()
                    return
                }
                applySnapshotToRuntime(snap)
            }
            if !sawReady {
                error = lastPhase == "error"
                    ? "Échec du chargement du modèle"
                    : "Le modèle ne confirme pas encore son chargement — réessaie ou vérifie LM Studio."
                // Ne pas forcer un rollback UI si le serveur a peut-être avancé : re-sync sélection.
                if let snap = try? await client.runtimeSnapshot(), let loaded = snap.loadedModel {
                    selectedModel = loaded
                    runtimeStatus = snap.phase == "ready" ? "READY" : runtimeStatus
                } else {
                    selectedModel = previous
                }
            }
            modelSwitching = false
        } catch {
            selectedModel = previous
            modelSwitching = false
            self.error = error.localizedDescription
            await refreshRuntimeStatus()
        }
    }

    private func applyReasoning(_ mode: String) {
        let previous = reasoningEffort
        guard mode != previous else { return }
        reasoningEffort = mode
        Task {
            do {
                try await client.patchConversation(id: conversation.id, reasoningEffort: mode)
            } catch {
                reasoningEffort = previous
                self.error = error.localizedDescription
            }
        }
    }

    private func beginEdit(_ msg: MessageDTO) {
        guard msg.role == "user" else { return }
        editingMessageId = msg.id
        draft = msg.content
        AppHaptics.light()
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        let tempId = "local-\(UUID().uuidString)"
        uploading = true
        defer {
            uploading = false
            photoItem = nil
        }

        do {
            guard let picked = try await item.loadTransferable(type: PickedImageData.self) else { return }
            let thumb = await Task.detached(priority: .userInitiated) {
                ImagePipeline.thumbnail(data: picked.data, maxPixelSize: 280)
            }.value
            let thumbData = thumb?.jpegData(compressionQuality: 0.78)
            pendingAttachments.append(
                UploadedAttachment(
                    id: tempId,
                    filename: "envoi…",
                    mimeType: "image/jpeg",
                    sizeBytes: picked.data.count,
                    previewData: thumbData,
                    isUploading: true
                )
            )

            let (compressed, mime) = await Task.detached(priority: .userInitiated) {
                ImagePipeline.compressForUpload(picked.data)
            }.value
            let filename = "photo-\(UUID().uuidString.prefix(8)).jpg"
            let uploaded = try await client.uploadAttachment(
                conversationId: conversation.id,
                filename: filename,
                mimeType: mime,
                fileData: compressed
            )
            if let idx = pendingAttachments.firstIndex(where: { $0.id == tempId }) {
                pendingAttachments[idx] = UploadedAttachment(
                    id: uploaded.id,
                    filename: uploaded.filename,
                    mimeType: uploaded.mimeType,
                    sizeBytes: uploaded.sizeBytes,
                    previewData: thumbData ?? compressed,
                    isUploading: false
                )
            }
        } catch {
            pendingAttachments.removeAll { $0.id == tempId }
            self.error = error.localizedDescription
        }
    }

    private func handleImportedDoc(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let err):
            self.error = err.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let tempId = "local-\(UUID().uuidString)"
            uploading = true
            defer { uploading = false }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let name = url.lastPathComponent
                let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                    ?? "application/octet-stream"
                let isImage = mime.hasPrefix("image/")
                var payload = data
                var outMime = mime
                var preview: Data?
                if isImage {
                    let thumb = ImagePipeline.thumbnail(data: data, maxPixelSize: 280)
                    preview = thumb?.jpegData(compressionQuality: 0.78)
                    let compressed = ImagePipeline.compressForUpload(data)
                    payload = compressed.0
                    outMime = compressed.1
                }
                pendingAttachments.append(
                    UploadedAttachment(
                        id: tempId,
                        filename: name,
                        mimeType: outMime,
                        sizeBytes: payload.count,
                        previewData: preview,
                        isUploading: true
                    )
                )
                let uploaded = try await client.uploadAttachment(
                    conversationId: conversation.id,
                    filename: name,
                    mimeType: outMime,
                    fileData: payload
                )
                if let idx = pendingAttachments.firstIndex(where: { $0.id == tempId }) {
                    pendingAttachments[idx] = UploadedAttachment(
                        id: uploaded.id,
                        filename: uploaded.filename,
                        mimeType: uploaded.mimeType,
                        sizeBytes: uploaded.sizeBytes,
                        previewData: preview,
                        isUploading: false
                    )
                }
            } catch {
                pendingAttachments.removeAll { $0.id == tempId }
                self.error = error.localizedDescription
            }
        }
    }

    private func removePending(_ att: UploadedAttachment) async {
        pendingAttachments.removeAll { $0.id == att.id }
        if !att.id.hasPrefix("local-") {
            try? await client.deleteAttachment(id: att.id)
        }
    }

    private func regenerate() async {
        guard !isSending else { return }
        if let lastUser = messages.last(where: { $0.role == "user" }) {
            if let idx = messages.lastIndex(where: { $0.id == lastUser.id }) {
                messages = Array(messages.prefix(through: idx))
            }
        }
        await send(options: ChatSendOptions(regenerate: true, mode: chatMode))
    }

    private func send(options: ChatSendOptions? = nil, forcedText: String? = nil, hideUserMessage: Bool = false) async {
        let text = (forcedText ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = pendingAttachments.filter { !$0.isUploading && !$0.id.hasPrefix("local-") }.map(\.id)
        let isEdit = editingMessageId != nil
        guard !text.isEmpty || !ids.isEmpty || options?.regenerate == true else { return }

        var opts = options ?? ChatSendOptions(attachmentIds: ids, mode: chatMode)
        if let editId = editingMessageId {
            opts.editMessageId = editId
        }
        if opts.activeContext == nil {
            opts.activeContext = forcedActiveContext
        }

        suppressAssistantNarration = false

        var immediateThinking: ThinkingKind = chatMode == "agent" ? .preparing : .reflecting
        let lower = text.lowercased()
        if lower.contains("moi-même") || lower.contains("moi meme") || lower.contains("à moi") || lower.contains("a moi") {
            immediateThinking = .custom("Recherche du destinataire…")
        } else if lower.contains("mail") || lower.contains("email") || lower.contains("brouillon") || lower.contains("écris") || lower.contains("ecris") {
            immediateThinking = .custom("Préparation du brouillon…")
        } else if lower.contains("résum") || lower.contains("resum") {
            immediateThinking = .custom("Analyse du message…")
        } else if lower.contains("répond") || lower.contains("repond") {
            immediateThinking = .custom("Préparation de la réponse…")
        }
        thinkingKind = immediateThinking

        if options?.regenerate != true {
            draft = ""
            if !isEdit && !hideUserMessage {
                let localAtts: [MessageAttachmentDTO]? = ids.isEmpty ? nil : pendingAttachments
                    .filter { ids.contains($0.id) }
                    .map {
                        MessageAttachmentDTO(
                            id: $0.id,
                            filename: $0.filename,
                            mimeType: $0.mimeType,
                            sizeBytes: $0.sizeBytes,
                            type: $0.typeHint
                        )
                    }
                messages.append(
                    MessageDTO(
                        id: "local-\(UUID().uuidString)",
                        role: "user",
                        content: text.isEmpty ? "📎 Pièce jointe" : text,
                        createdAt: nil,
                        attachments: localAtts
                    )
                )
            } else if !hideUserMessage, let editId = editingMessageId,
                      let idx = messages.firstIndex(where: { $0.id == editId }) {
                messages[idx] = MessageDTO(
                    id: editId,
                    role: "user",
                    content: text,
                    createdAt: messages[idx].createdAt,
                    attachments: messages[idx].attachments
                )
                messages = Array(messages.prefix(through: idx))
            }
            pendingAttachments = []
            editingMessageId = nil
        }

        isSending = true
        streamingText = ""
        // Ne pas écraser un statut Mail déjà posé (brouillon / destinataire / résumé).
        if case .custom = thinkingKind {
            // conserver
        } else if chatMode == "agent" {
            thinkingKind = nil
        } else if thinkingKind == nil {
            thinkingKind = .reflecting
        }
        error = nil
        streamSources = []
        streamMailHandoff = nil
        streamFilesHandoff = nil
        streamFilesFound = []
        agentActivity = AgentActivityState()
        showScrollDown = false
        runtimeStatus = "BUSY"

        do {
            try await client.sendChat(
                conversationId: conversation.id,
                message: text,
                options: opts,
                streaming: streamingService
            ) { event in
                Task { @MainActor in handleSSE(type: event.type, obj: event.payload) }
            }
            if Task.isCancelled {
                // Stop / arrière-plan : finalizeStoppedStream (ou scenePhase) a déjà géré le partial.
                thinkingKind = nil
                isSending = false
                sendTask = nil
                return
            }
            lastSources = streamSources
            lastMailHandoff = streamMailHandoff
            lastFilesHandoff = streamFilesHandoff
            let finalFound = streamFilesFound
            // Garder le texte streamé : MessageBubble masque la narration fichier redondante.
            // Vider ici provoquait un flash (vide ~1s pendant loadMessages, puis réapparition).
            let finalText = streamingText
            let finalSources = streamSources
            let finalMail = streamMailHandoff
            let finalFiles = streamFilesHandoff
            let promoteId = streamingAssistantId ?? "asst-\(UUID().uuidString)"
            // Promote in-place AVANT clear/reload — évite le trou « disparaît puis réapparaît ».
            if !finalText.isEmpty || !finalFound.isEmpty || finalMail != nil || finalFiles != nil || !finalSources.isEmpty {
                if let idx = messages.firstIndex(where: { $0.id == promoteId }) {
                    messages[idx] = MessageDTO(
                        id: promoteId,
                        role: "assistant",
                        content: finalText,
                        createdAt: messages[idx].createdAt,
                        attachments: messages[idx].attachments
                    )
                } else {
                    messages.append(
                        MessageDTO(id: promoteId, role: "assistant", content: finalText, createdAt: nil)
                    )
                }
                let meta = MessageChromeMeta(
                    sources: finalSources,
                    mailHandoff: finalMail,
                    filesHandoff: finalFiles,
                    filesFound: finalFound
                )
                chromeById[promoteId] = meta
                ConversationSessionStore.setChrome(
                    meta,
                    conversationId: conversation.id,
                    messageId: promoteId
                )
            }
            streamingText = ""
            suppressAssistantNarration = false
            // ID serveur déjà stable (assistant_start) : sync soft sans remplacer l’identité ForEach.
            if streamingAssistantId != nil {
                streamingAssistantId = nil
                scrollToken += 1
                Task {
                    contextSnapshot = try? await client.conversationContext(conversationId: conversation.id)
                }
            } else {
                await loadMessages(preserveAssistantId: promoteId)
                if let last = messages.last(where: { $0.role == "assistant" }) {
                    var meta = chromeById[last.id] ?? MessageChromeMeta()
                    if meta.sources.isEmpty { meta.sources = finalSources }
                    if meta.mailHandoff == nil { meta.mailHandoff = finalMail }
                    if meta.filesHandoff == nil { meta.filesHandoff = finalFiles }
                    if meta.filesFound.isEmpty { meta.filesFound = finalFound }
                    chromeById[last.id] = meta
                    ConversationSessionStore.setChrome(
                        meta,
                        conversationId: conversation.id,
                        messageId: last.id
                    )
                }
                scrollToken += 1
            }
        } catch is CancellationError {
            thinkingKind = nil
        } catch {
            self.error = error.localizedDescription
            canRetrySend = true
            if case APIClientError.unauthorized = error {
                await session.logout()
            }
        }
        isSending = false
        sendTask = nil
    }

    private func resolveFileAction(confirm: Bool) async {
        guard let pending = pendingFileAction else { return }
        confirmingFileAction = true
        defer { confirmingFileAction = false }
        do {
            try await client.confirmFilesAction(
                actionId: pending.id,
                confirmationToken: pending.confirmationToken,
                confirm: confirm
            )
            pendingFileAction = nil
            thinkingKind = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var shouldShowAgentStrip: Bool {
        agentActivity.visible || agentActivity.webPhase != .idle || agentActivity.completed || agentActivity.lastError != nil
    }

    private func finalizeStoppedStream() {
        isSending = false
        thinkingKind = nil
        if agentActivity.visible || agentActivity.webPhase != .idle {
            agentActivity.completed = true
            agentActivity.visible = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                withAnimation(.easeOut(duration: 0.25)) {
                    agentActivity = AgentActivityState()
                }
            }
        } else {
            agentActivity = AgentActivityState()
        }
        if !streamingText.isEmpty {
            messages.append(
                MessageDTO(
                    id: "partial-\(UUID().uuidString)",
                    role: "assistant",
                    content: streamingText,
                    createdAt: nil
                )
            )
            streamingText = ""
            scrollToken += 1
        }
        Task { @MainActor in
            runtimeStatus = (try? await client.runtimeStatus()) ?? runtimeStatus
        }
        AppHaptics.light()
    }

    private func handleSSE(type: String, obj: [String: Any]) {
        switch type {
        case "token":
            if let c = obj["content"] as? String {
                streamingText += c
                if let id = streamingAssistantId,
                   let idx = messages.firstIndex(where: { $0.id == id }) {
                    let prev = messages[idx]
                    messages[idx] = MessageDTO(
                        id: id,
                        role: "assistant",
                        content: prev.content + c,
                        createdAt: prev.createdAt,
                        attachments: prev.attachments
                    )
                }
            }
            thinkingKind = nil
        case "status", "thinking", "runtime_status":
            if type == "runtime_status", let st = obj["status"] as? String {
                runtimeStatus = st
            }
            if !agentActivity.visible {
                let msg = (obj["message"] as? String) ?? (obj["status"] as? String)
                thinkingKind = ThinkingKind.fromSSE(type: type, message: msg)
            }
        case "tool_start":
            let tool = (obj["tool"] as? String) ?? (obj["name"] as? String) ?? ""
            if agentActivity.visible {
                agentActivity.currentStepTitle = AgentToolLabels.humanize(tool.isEmpty ? "outil" : tool)
                agentActivity.phase = "executing"
            } else if tool.lowercased().contains("search") {
                agentActivity.webPhase = .searching
                agentActivity.webQuery = (obj["query"] as? String) ?? tool
                thinkingKind = .searching
            } else {
                thinkingKind = ThinkingKind.fromSSE(type: type, message: tool)
            }
        case "tool_done", "tool_result":
            if agentActivity.webPhase == .searching || agentActivity.webPhase == .analyzing {
                agentActivity.webPhase = .analyzing
            }
            if agentActivity.visible {
                if let summary = obj["summary"] as? String, !summary.isEmpty {
                    agentActivity.currentStepTitle = AgentToolLabels.humanize(summary)
                }
            } else if !agentActivity.visible {
                thinkingKind = .preparing
            }
        case "tool_error":
            let raw = (obj["message"] as? String) ?? (obj["error"] as? String)
            if agentActivity.visible {
                agentActivity.lastError = AgentToolLabels.friendlyError(raw)
            } else {
                thinkingKind = .custom(AgentToolLabels.friendlyError(raw))
            }
        case "web_search":
            let q = (obj["query"] as? String) ?? (obj["message"] as? String) ?? "Recherche web…"
            agentActivity.webQuery = q
            agentActivity.webPhase = .searching
            if !agentActivity.visible {
                thinkingKind = .searching
            }
        case "agent_start":
            thinkingKind = nil
            agentActivity.visible = true
            agentActivity.completed = false
            agentActivity.lastError = nil
            agentActivity.phase = "planning"
        case "agent_plan":
            thinkingKind = nil
            agentActivity.visible = true
            agentActivity.phase = "planning"
            if let plan = obj["plan"] as? [String: Any],
               let steps = plan["steps"] as? [[String: Any]] {
                agentActivity.planSteps = steps.enumerated().map { idx, s in
                    AgentPlanStep(
                        id: (s["id"] as? String) ?? "\(idx)",
                        title: (s["title"] as? String) ?? (s["goal"] as? String) ?? "Étape \(idx + 1)",
                        status: "pending"
                    )
                }
                agentActivity.totalSteps = agentActivity.planSteps.count
            }
        case "agent_step", "agent_step_update":
            thinkingKind = nil
            agentActivity.visible = true
            agentActivity.phase = "executing"
            if let idx = obj["stepIndex"] as? Int { agentActivity.stepIndex = idx }
            if let total = obj["totalSteps"] as? Int { agentActivity.totalSteps = total }
            if let stepId = obj["stepId"] as? String,
               let i = agentActivity.planSteps.firstIndex(where: { $0.id == stepId }) {
                let st = (obj["status"] as? String) ?? "running"
                agentActivity.planSteps[i].status = st
                agentActivity.currentStepTitle = agentActivity.planSteps[i].title
                if st == "error" {
                    agentActivity.lastError = AgentToolLabels.friendlyError(obj["message"] as? String)
                }
            } else if let msg = obj["message"] as? String {
                agentActivity.currentStepTitle = msg
            }
        case "agent_action_start":
            agentActivity.visible = true
            agentActivity.phase = "executing"
            if let action = obj["action"] as? [String: Any] {
                let raw = (action["summary"] as? String) ?? (action["type"] as? String)
                agentActivity.currentStepTitle = raw.map(AgentToolLabels.humanize)
            }
        case "agent_done", "agent_status":
            if type == "agent_done" {
                agentActivity.phase = "synthesis"
            }
            if let msg = obj["message"] as? String, !msg.isEmpty {
                agentActivity.currentStepTitle = msg
            }
        case "assistant_start":
            if let id = obj["messageId"] as? String {
                streamingAssistantId = id
                if messages.firstIndex(where: { $0.id == id }) == nil {
                    messages.append(
                        MessageDTO(id: id, role: "assistant", content: "", createdAt: nil)
                    )
                }
            }
            if !agentActivity.visible {
                thinkingKind = .preparing
            }
        case "assistant_discard":
            if let id = obj["messageId"] as? String, streamingAssistantId == id {
                streamingText = ""
                streamingAssistantId = nil
                if let idx = messages.firstIndex(where: { $0.id == id }) {
                    messages.remove(at: idx)
                }
                if !agentActivity.visible {
                    thinkingKind = .preparing
                }
            }
        case "sources":
            agentActivity.webPhase = .done
            if let arr = obj["sources"] as? [[String: Any]] {
                streamSources = arr.enumerated().compactMap { idx, s in
                    guard let url = s["url"] as? String else { return nil }
                    return SearchSourceDTO(
                        id: "\(idx)-\(url)",
                        title: (s["title"] as? String) ?? url,
                        url: url,
                        domain: s["domain"] as? String,
                        snippet: s["snippet"] as? String
                    )
                }
            }
        case "context_snapshot":
            if let snap = obj["snapshot"] as? [String: Any] {
                contextSnapshot = ContextSnapshotDTO(
                    conversationTokens: snap["conversationTokens"] as? Int,
                    contextLengthMax: snap["contextLengthMax"] as? Int,
                    budgetTokens: snap["budgetTokens"] as? Int,
                    usedPercent: snap["usedPercent"] as? Double,
                    remainingPercent: snap["remainingPercent"] as? Double
                )
            }
        case "file_action_pending":
            let actionId = (obj["actionId"] as? String) ?? UUID().uuidString
            let token = (obj["confirmationToken"] as? String) ?? ""
            let op = (obj["op"] as? String) ?? "action"
            var detail = op
            if let payload = obj["payload"] as? [String: Any] {
                let dest = payload["destRelativePath"] as? String
                let src = payload["sourceRelativePath"] as? String
                detail = [src, dest].compactMap { $0 }.joined(separator: " → ")
                if detail.isEmpty { detail = (obj["notice"] as? String) ?? op }
            } else if let notice = obj["notice"] as? String {
                detail = notice
            }
            pendingFileAction = PendingFileAction(
                id: actionId,
                confirmationToken: token,
                op: op,
                detail: detail,
                expiresAt: obj["expiresAt"] as? String
            )
            thinkingKind = nil
        case "memory_saved":
            if let memories = obj["memories"] as? [[String: Any]], let first = memories.first {
                let cat = (first["category"] as? String) ?? "mémoire"
                let content = (first["content"] as? String) ?? (first["text"] as? String) ?? "Souvenir enregistré"
                memoryNotice = "\(cat) · \(content)"
            } else {
                memoryNotice = "Mémoire enregistrée"
            }
        case "mail_handoff":
            streamMailHandoff = MailHandoffDTO(
                intent: obj["intent"] as? String,
                reason: obj["reason"] as? String,
                query: obj["query"] as? String,
                threadId: obj["threadId"] as? String,
                label: obj["label"] as? String
            )
        case "files_handoff":
            streamFilesHandoff = FilesHandoffDTO(
                intent: obj["intent"] as? String,
                reason: obj["reason"] as? String,
                query: obj["query"] as? String,
                rootId: obj["rootId"] as? String
            )
        case "files_found":
            if let arr = obj["files"] as? [[String: Any]] {
                let parsed: [FilesFoundFileDTO] = arr.compactMap { f in
                    guard let id = f["fileId"] as? String, !id.isEmpty else { return nil }
                    return FilesFoundFileDTO(
                        id: id,
                        filename: (f["filename"] as? String) ?? "fichier",
                        relativePath: f["relativePath"] as? String,
                        rootId: f["rootId"] as? String,
                        sizeBytes: f["sizeBytes"] as? Int,
                        mtimeMs: f["mtimeMs"] as? Double,
                        extensionHint: f["extension"] as? String
                    )
                }
                streamFilesFound = parsed
                if !parsed.isEmpty {
                    suppressAssistantNarration = true
                    // Ne pas vider streamingText ici — provoque un flash « disparaît / réapparaît ».
                }
                if let id = streamingAssistantId {
                    var chrome = chromeById[id] ?? MessageChromeMeta()
                    chrome.filesFound = parsed
                    chromeById[id] = chrome
                    ConversationSessionStore.mergeChrome(
                        chrome,
                        conversationId: conversation.id,
                        messageId: id
                    )
                }
            }
        case "draft_preview":
            if let draft = obj["draft"] as? [String: Any] {
                let id = (draft["id"] as? String) ?? (draft["draftId"] as? String)
                let body =
                    (draft["bodyText"] as? String)
                    ?? (draft["body"] as? String)
                    ?? (draft["text"] as? String)
                    ?? ""
                if let id, !id.isEmpty {
                    draftCardId = id
                    draftCardText = body
                    draftCardTo = ((draft["to"] as? [String]) ?? []).joined(separator: ", ")
                    draftCardSubject = (draft["subject"] as? String) ?? ""
                    draftCardStatus = "Brouillon"
                    draftInConversation = true
                    draftCardStreaming = false
                    suppressAssistantNarration = true
                    streamingText = ""
                    draftCardEditing = false
                    thinkingKind = nil
                }
            }
        case "conversation_title":
            if let title = obj["title"] as? String, !title.isEmpty {
                conversationTitle = title
            }
        case "error":
            if let code = obj["code"] as? String, code == "ABORTED" {
                thinkingKind = nil
                agentActivity = AgentActivityState()
                return
            }
            let msg = obj["message"] as? String ?? "Erreur"
            if agentActivity.visible {
                agentActivity.lastError = AgentToolLabels.friendlyError(msg)
            }
            error = AgentToolLabels.friendlyError(msg)
        case "done":
            thinkingKind = nil
            if agentActivity.visible || agentActivity.webPhase != .idle {
                agentActivity.completed = true
                agentActivity.phase = "synthesis"
                agentActivity.visible = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    withAnimation(.easeOut(duration: 0.25)) {
                        agentActivity = AgentActivityState()
                    }
                }
            } else {
                agentActivity = AgentActivityState()
            }
            Task { @MainActor in
                runtimeStatus = (try? await client.runtimeStatus()) ?? runtimeStatus
            }
            let chrome = MessageChromeMeta(
                sources: streamSources,
                mailHandoff: streamMailHandoff,
                filesHandoff: streamFilesHandoff,
                filesFound: streamFilesFound
            )
            if let id = streamingAssistantId ?? (obj["messageId"] as? String) {
                chromeById[id] = chrome
            }
            lastSources = streamSources
            lastMailHandoff = streamMailHandoff
            lastFilesHandoff = streamFilesHandoff
            lastFilesFound = streamFilesFound
            if let title = obj["title"] as? String, !title.isEmpty {
                conversationTitle = title
            }
            Task { contextSnapshot = try? await client.conversationContext(conversationId: conversation.id) }
            AppHaptics.success()
        default:
            break
        }
    }

}

struct PendingAttachmentCard: View {
    let attachment: UploadedAttachment
    let onRemove: () -> Void

    private var sizeLabel: String {
        let kind = attachment.isImage ? "Image" : "Document"
        return "\(kind) · \(ByteCountFormatter.string(fromByteCount: Int64(attachment.sizeBytes), countStyle: .file))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let data = attachment.previewData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            AppTheme.surfaceHover.opacity(0.7)
                            Image(systemName: attachment.isImage ? "photo" : "doc.fill")
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }
                .frame(height: 64)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                .overlay {
                    if attachment.isUploading {
                        ZStack {
                            Color.black.opacity(0.45)
                            ProgressView().tint(.white)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                    }
                }

                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.65))
                        .font(.system(size: 18))
                }
                .offset(x: 4, y: -4)
            }

            Text(attachment.filename)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AppTheme.foreground)
                .lineLimit(1)
            Text(attachment.error ?? sizeLabel)
                .font(.system(size: 10))
                .foregroundStyle(attachment.error == nil ? AppTheme.muted : AppTheme.danger)
                .lineLimit(1)
        }
        .padding(8)
        .frame(width: 120, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct LightboxItem: Identifiable {
    let id: String
    let image: UIImage
    let filename: String?
}

struct ImageLightboxView: View {
    let item: LightboxItem
    let onClose: () -> Void
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: item.image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = max(1, min(4, lastScale * value))
                        }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= 1.01 {
                                withAnimation(.easeOut) {
                                    scale = 1
                                    lastScale = 1
                                    offset = .zero
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if scale > 1 { offset = value.translation }
                        }
                )
                .padding()
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding()
                }
                Spacer()
                if let name = item.filename {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 24)
                }
            }
        }
    }
}
