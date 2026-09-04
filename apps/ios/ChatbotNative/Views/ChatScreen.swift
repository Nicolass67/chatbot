import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ChatScreen: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(AppNavigation.self) private var nav
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var lastSources: [SearchSourceDTO] = []
    @State private var lastMailHandoff: MailHandoffDTO?
    @State private var lastFilesHandoff: FilesHandoffDTO?
    @State private var agentActivity = AgentActivityState()
    @State private var runtimeStatus: String = "…"
    @State private var showScrollDown = false
    @State private var scrollToken = 0
    @State private var memoryNotice: String?
    @State private var pendingFileAction: PendingFileAction?
    @State private var confirmingFileAction = false
    @State private var chromeById: [String: MessageChromeMeta] = [:]
    @State private var streamingAssistantId: String?
    @State private var contextSnapshot: ContextSnapshotDTO?
    @State private var streamingService = ChatStreamingService()

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

    /// Garde le chrome Thinking à l’écran pendant le scénario UITest `thinking`.
    private var uiTestKeepThinking: Bool {
        UITestMode.isActive && UITestMode.sseScenario == "thinking"
    }

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(spacing: 0) {
                messageScroll
                if shouldShowAgentStrip {
                    AgentActivityView(state: agentActivity)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else if let thinkingKind, isSending || uiTestKeepThinking {
                    ThinkingStatusView(kind: thinkingKind)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                        .transition(.opacity)
                        .accessibilityIdentifier(A11yID.Chat.thinking)
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
            await loadMessages()
            await loadSettings()
            runtimeStatus = (try? await client.runtimeStatus()) ?? "UNKNOWN"
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
        }
        .onDisappear {
            if isSending {
                sendTask?.cancel()
                Task { await streamingService.cancel() }
            }
        }
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
                                }
                            )
                            .id(msg.id)
                        }
                        if !streamingText.isEmpty {
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
                                }
                            )
                            .id("streaming")
                        }
                        Color.clear.frame(height: 8).id("bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: streamingText) { _, text in
                    guard !showScrollDown, !text.isEmpty else { return }
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: messages.count) { _, _ in
                    showScrollDown = false
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: scrollToken) { _, _ in
                    showScrollDown = false
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: isSending) { _, sending in
                    if !sending {
                        Task { @MainActor in
                            // Double pass : layout Markdown final + reload messages.
                            try? await Task.sleep(nanoseconds: 40_000_000)
                            proxy.scrollTo("bottom", anchor: .bottom)
                            try? await Task.sleep(nanoseconds: 120_000_000)
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12).onChanged { _ in
                        if isSending { showScrollDown = true }
                    }
                )
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

    private var emptyThread: some View {
        EmptyChatCanvas { suggestion in
            draft = suggestion
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
                onModeChange: { mode in Task { await applyMode(mode) } },
                onWebChange: { enabled in Task { await applyWeb(enabled) } },
                onModelChange: { modelId in Task { await applyModel(modelId) } },
                onReasoningChange: { mode in Task { await applyReasoning(mode) } },
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
        // XCUITest : typeText ne met pas toujours à jour le @Binding SwiftUI à temps.
        // En UITestMode le bouton reste armé ; `send()` injecte un texte défaut si besoin.
        if UITestMode.isActive && !isSending && !uploading {
            return true
        }
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !pendingAttachments.isEmpty) && !uploading && !pendingAttachments.contains(where: \.isUploading)
    }

    private func loadMessages() async {
        do {
            messages = try await client.listMessages(conversationId: conversation.id)
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

    private func loadSettings() async {
        async let web = client.getWebSearchEnabled()
        async let settings = client.getSettings()
        async let modelList = client.listModels()
        webSearchEnabled = (try? await web) ?? false
        models = (try? await modelList) ?? []
        if let s = try? await settings {
            selectedModel = (s["selectedModel"] as? String) ?? ""
            if reasoningEffort.isEmpty {
                reasoningEffort = (s["defaultReasoningEffort"] as? String) ?? ""
            }
        }
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

    private func applyMode(_ next: String) async {
        do {
            try await client.patchConversationMode(id: conversation.id, mode: next)
            chatMode = next
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func applyWeb(_ next: Bool) async {
        do {
            try await client.setWebSearchEnabled(next)
            webSearchEnabled = next
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func applyModel(_ modelId: String) async {
        modelSwitching = true
        defer { modelSwitching = false }
        do {
            try await client.selectModel(modelId)
            selectedModel = modelId
            await refreshReasoningCaps()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func applyReasoning(_ mode: String) async {
        do {
            try await client.patchConversation(id: conversation.id, reasoningEffort: mode)
            reasoningEffort = mode
        } catch {
            self.error = error.localizedDescription
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

    private func send(options: ChatSendOptions? = nil) async {
        var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && UITestMode.isActive && options?.regenerate != true {
            let forced = ProcessInfo.processInfo.environment["CHATBOT_UI_FORCE_MESSAGE"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            text = forced.isEmpty ? "UITest" : forced
        }
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

        if options?.regenerate != true {
            draft = ""
            if !isEdit {
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
            } else if let editId = editingMessageId,
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
        if chatMode == "agent" && !(UITestMode.isActive && UITestMode.sseScenario == "thinking") {
            thinkingKind = nil
        } else {
            thinkingKind = .reflecting
        }
        error = nil
        streamSources = []
        streamMailHandoff = nil
        streamFilesHandoff = nil
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
            let finalText = streamingText
            let finalSources = streamSources
            let finalMail = streamMailHandoff
            let finalFiles = streamFilesHandoff
            // Retirer le bubble stream avant le reload — évite le double layout / décalage.
            streamingText = ""
            await loadMessages()
            if let last = messages.last(where: { $0.role == "assistant" }), !finalSources.isEmpty || finalMail != nil || finalFiles != nil {
                chromeById[last.id] = MessageChromeMeta(
                    sources: finalSources,
                    mailHandoff: finalMail,
                    filesHandoff: finalFiles
                )
            } else if messages.last(where: { $0.role == "assistant" }) == nil, !finalText.isEmpty {
                let id = "asst-\(UUID().uuidString)"
                messages.append(
                    MessageDTO(id: id, role: "assistant", content: finalText, createdAt: nil)
                )
                chromeById[id] = MessageChromeMeta(
                    sources: finalSources,
                    mailHandoff: finalMail,
                    filesHandoff: finalFiles
                )
            }
            scrollToken += 1
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
        if !(UITestMode.isActive && UITestMode.sseScenario == "thinking") {
            thinkingKind = nil
        }
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
        runtimeStatus = "READY"
        AppHaptics.light()
    }

    private func handleSSE(type: String, obj: [String: Any]) {
        switch type {
        case "token":
            if let c = obj["content"] as? String { streamingText += c }
            // En scénario Thinking UITest, garder le chrome visible pour la capture PNG.
            let keepThinking = UITestMode.isActive && UITestMode.sseScenario == "thinking"
            if !keepThinking {
                thinkingKind = nil
            }
        case "status", "thinking", "runtime_status":
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
            }
            if !agentActivity.visible {
                thinkingKind = .preparing
            }
        case "assistant_discard":
            if let id = obj["messageId"] as? String, streamingAssistantId == id {
                streamingText = ""
                streamingAssistantId = nil
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
            if !(UITestMode.isActive && UITestMode.sseScenario == "thinking") {
                thinkingKind = nil
            }
            if agentActivity.visible || agentActivity.webPhase != .idle {
                agentActivity.completed = true
                agentActivity.phase = "synthesis"
                agentActivity.visible = true
                let keepAgent = UITestMode.isActive
                    && (UITestMode.sseScenario == "agent" || UITestMode.sseScenario == "agent-error")
                if !keepAgent {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        withAnimation(.easeOut(duration: 0.25)) {
                            agentActivity = AgentActivityState()
                        }
                    }
                }
            } else {
                agentActivity = AgentActivityState()
            }
            runtimeStatus = "READY"
            let chrome = MessageChromeMeta(
                sources: streamSources,
                mailHandoff: streamMailHandoff,
                filesHandoff: streamFilesHandoff
            )
            if let id = streamingAssistantId ?? (obj["messageId"] as? String) {
                chromeById[id] = chrome
            }
            lastSources = streamSources
            lastMailHandoff = streamMailHandoff
            lastFilesHandoff = streamFilesHandoff
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
