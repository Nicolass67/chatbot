import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

/// Buffer mutable hors invalidation SwiftUI (tokens SSE à haute cadence).
private final class ChatStreamAccum {
    var text = ""
}

/// Distances scroll pour pin-to-bottom + pagination historique.
private struct ChatScrollMetrics: Equatable {
    var distanceToTop: CGFloat
    var distanceToBottom: CGFloat
    var viewportHeight: CGFloat
}

struct ChatScreen: View {
    @Environment(\.themeRevision) private var themeRevision
    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var infra: InfrastructureStore
    @Environment(AppNavigation.self) private var nav
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    let conversation: ConversationDTO
    var onOpenHistory: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil
    /// Scope forcé (Assistant Mail/Files). Nil = Chat général.
    var forcedScope: ConversationScope? = nil
    var forcedActiveContext: ActiveContextHint? = nil
    /// Clé de persistance folder:/file:/… (sinon on tombait sur `__global__` et on écrasait la conv).
    var persistenceKeyOverride: String? = nil
    /// Fermeture explicite de la sheet Assistant (évite le no-op de `dismiss` dans NavigationStack).
    var onRequestClose: (() -> Void)? = nil

    @State private var messages: [MessageDTO] = []
    @State private var draft = ""
    @State private var streamingText = ""
    @State private var thinkingKind: ThinkingKind?
    @State private var isSending = false
    @State private var sendGeneration: UInt64 = 0
    @State private var error: String?
    @State private var sendTask: Task<Void, Never>?
    @State private var pendingAttachments: [UploadedAttachment] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var chatMode: String = "chat"
    @State private var webSearchEnabled = false
    @AppStorage("composerToolChannel") private var toolChannelRaw: String = ComposerToolChannel.web.rawValue
    @State private var editingMessageId: String?
    @State private var lightbox: LightboxItem?
    @State private var conversationTitle: String = ""
    @State private var showDocImporter = false
    @State private var showTools = false
    @State private var quickLookURL: IdentifiedURL?
    /// Garde le SSE vivant quand l’utilisateur passe une autre app (évite AbortSignal serveur).
    @State private var chatBackgroundTaskId: UIBackgroundTaskIdentifier = .invalid
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
    @State private var draftCardAttachments: [EmailDraftAttachmentChip] = []
    @State private var draftRecipientSuggestions: [MailRecipientSuggestion] = []
    @State private var draftRecipientSuggestTask: Task<Void, Never>?
    @State private var draftCardEditing = false
    @State private var draftCardBusy = false
    @State private var draftCardStreaming = false
    @State private var draftCardSent = false
    /// Croix : brouillon masqué du fil (pas annulé serveur) — récupérable.
    @State private var draftCardCollapsed = false
    @State private var confirmSendDraft = false
    @State private var draftInConversation = false
    @State private var lastSources: [SearchSourceDTO] = []
    @State private var lastMailHandoff: MailHandoffDTO?
    @State private var lastFilesHandoff: FilesHandoffDTO?
    @State private var lastFilesFound: [FilesFoundFileDTO] = []
    @State private var agentActivity = AgentActivityState()
    @State private var runtimeStatus: String = "…"
    @State private var showScrollDown = false
    /// Hauteur totale du chrome flottant pour le padding du fil.
    @State private var floatingChromeHeight: CGFloat = 168
    /// Safe area bas (tab bar + home indicator) — lift du composer au-dessus de Chat/Mail/Files.
    @State private var bottomSafeInset: CGFloat = 83
    /// Clavier visible → ne pas re-pousser le composer (safe area clavier déjà appliquée).
    @State private var keyboardLiftActive = false
    /// Ouverture clavier alors qu’on était collé en bas → re-stick (sinon laisser la position).
    @State private var stickBottomThroughKeyboard = false
    /// Collé en bas → suivi auto du stream. Remontée utilisateur / pin envoi → false.
    @State private var isPinnedToBottom = true
    /// Pendant un scroll programmé (envoi / stream / bouton), ignore les pics de distance.
    @State private var suppressScrollGeometryUntil: Date = .distantPast
    /// Afficher « bas » seulement après une vraie remontée (pas quasi en bas).
    private let scrollShowButtonThreshold: CGFloat = 520
    /// Redescente : re-pin + masquer le bouton (hystérésis).
    private let scrollHideButtonThreshold: CGFloat = 160
    @State private var scrollToken = 0
    /// Hauteur visible du ScrollView — spacer pour ancrer le message user en haut.
    @State private var scrollViewportHeight: CGFloat = 0
    /// Après envoi : ancre ce message user en haut du viewport (style ChatGPT).
    @State private var pinToTopMessageId: String?
    @State private var pinToTopToken = 0
    /// Historique long : page récente + pages plus anciennes au scroll haut (RAM).
    /// Fenêtre bornée — trop de bulles SwiftUI = lag (markdown / pastilles).
    @State private var hasMoreOlderMessages = false
    @State private var isLoadingOlderMessages = false
    @State private var scrollAnchorAfterPrepend: String?
    /// Fenêtre récente bornée — trop de bulles SwiftUI = lag (surtout markdown / pastilles).
    private let historyInitialPageSize = 5
    private let historyOlderPageSize = 5
    private let historyLoadOlderOffsetY: CGFloat = 140
    @State private var memoryNotice: String?
    @State private var pendingFileAction: PendingFileAction?
    @State private var confirmingFileAction = false
    @State private var chromeById: [String: MessageChromeMeta] = [:]
    @State private var streamingAssistantId: String?
    @State private var tokenCoalesceBuffer = ""
    @State private var tokenFlushTask: Task<Void, Never>?
    @State private var lastStreamScrollAt = Date.distantPast
    /// Tick de scroll stream (~30 fps) — évite un onChange(streamingText) à chaque token.
    @State private var streamScrollTick = 0
    /// Accumulation tokens hors @Published : le texte affiché est poussé seulement au flush.
    @State private var streamAccum = ChatStreamAccum()
    @State private var runtimePollNs: UInt64 = 1_500_000_000
    @State private var contextSnapshot: ContextSnapshotDTO?
    @State private var streamingService = ChatStreamingService()
    /// Quand draft/files_found = résultat principal : ne pas promouvoir la narration textuelle.
    @State private var suppressAssistantNarration = false
    /// Bouton Améliorer : le prochain envoi composer = conseil pour le brouillon.
    @State private var draftImprovePending = false
    /// Le résultat d’amélioration doit aller dans la carte, pas le chat.
    @State private var awaitingDraftRewrite = false
    @State private var draftPreviewReceivedThisTurn = false
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
        let _ = themeRevision
        // Hiérarchie réelle (sous la UITabBar système) :
        // messages → fade → composer/contrôles.
        // Un fade sibling de TabView dans MainTabView est AU-DESSUS de la tab bar
        // (prouvé par le test rouge qui masquait Chat/Mail/Files) — mauvais étage.
        //
        // CRITICAL : le ZStack doit ignorer la safe area bas. Sinon le composer est
        // déjà posé au-dessus de la tab bar, et un padding.bottom ajoute un 2e lift
        // (composer « trop haut » avec trou sous le chrome).
        ZStack(alignment: .bottom) {
            AmbientBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if let scope = forcedScope, scope == .mail {
                    PersistentProductActionsBar(
                        scope: scope,
                        hasMailThread: forcedActiveContext?.mailThreadId != nil,
                        hasDraft: draftCardVisible,
                        onAction: { action in
                            Task { await runQuickAction(action) }
                        }
                    )
                }
                messageScroll
            }

            // NIVEAU 2 — fade devant le chat, derrière le chrome.
            ViewportBottomFade(height: Self.bottomFadeHeight)

            // NIVEAU 3 — UI flottante nette, au-dessus du fade.
            composerFloatingChrome
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .background {
            GeometryReader { geo in
                let inset = geo.safeAreaInsets.bottom
                Color.clear
                    .onAppear { updateBottomSafeInset(inset) }
                    .onChange(of: inset) { _, value in updateBottomSafeInset(value) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            // Avant le shrink du viewport : mémoriser si on était vraiment en bas.
            if !stickBottomThroughKeyboard {
                stickBottomThroughKeyboard =
                    isPinnedToBottom && pinToTopMessageId == nil && !showScrollDown
            }
        }
        .navigationTitle(
            forcedScope != nil
                ? ""
                : (conversationTitle.isEmpty ? "Nouvelle conversation" : conversationTitle)
        )
        .tabRootNavigationChrome()
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
        .alert(
            "Envoyer ce mail ?",
            isPresented: $confirmSendDraft
        ) {
            Button("Annuler", role: .cancel) {}
            Button("Confirmer") {
                Task { await sendDraftCard() }
            }
        } message: {
            Text("À \(draftCardTo.isEmpty ? "le destinataire" : draftCardTo)\nObjet : \(draftCardSubject.isEmpty ? "(sans objet)" : draftCardSubject)")
        }
        .task {
            conversationTitle = conversation.title ?? ""
            chatMode = conversation.chatMode ?? "chat"
            reasoningEffort = conversation.reasoningEffort ?? ""
            chromeById = ConversationSessionStore.chrome(for: conversation.id)
            restoreDraftCardSnapshot()
            persistActiveConversation()
            if messages.isEmpty, let cached = TabMemoryCache.chat(conversationId: conversation.id), !cached.isEmpty {
                // Fenêtre récente seulement — pas tout le cache (RAM).
                if cached.count > historyInitialPageSize {
                    messages = Self.withoutLeakedDraftControlMessages(Array(cached.suffix(historyInitialPageSize)))
                    hasMoreOlderMessages = true
                } else {
                    messages = Self.withoutLeakedDraftControlMessages(cached)
                }
            }
            // Toujours resync serveur (hasMore + page bornée).
            await loadMessages()
            await restoreDraftCardFromServerIfNeeded()
            if !settingsHydrated {
                await loadSettings()
            }
            await refreshRuntimeStatus()
            let needsInfraRefresh =
                infra.status == nil
                || infra.lastRefresh.map { Date().timeIntervalSince($0) > 60 } ?? true
            if needsInfraRefresh {
                await infra.refresh()
            }
        }
        .task {
            while !Task.isCancelled {
                let chatVisible = forcedScope != nil || nav.selectedTab == .chat
                if chatVisible {
                    await refreshRuntimeStatus()
                    let busy = runtimeStatus.uppercased().contains("BUSY")
                        || runtimeStatus.uppercased().contains("LOAD")
                        || runtimeStatus.uppercased().contains("SWITCH")
                        || isSending
                    runtimePollNs = busy ? 1_500_000_000 : min(runtimePollNs * 2, 8_000_000_000)
                } else {
                    runtimePollNs = 8_000_000_000
                }
                try? await Task.sleep(nanoseconds: runtimePollNs)
            }
        }
        .onChange(of: messages) { _, msgs in
            // Cap cache : évite de réhydrater des fils géants en mémoire.
            // Cap serré : évite de réhydrater un fil trop long au retour d’onglet.
            let cap = historyInitialPageSize + historyOlderPageSize * 2
            let toStore = msgs.count > cap ? Array(msgs.suffix(cap)) : msgs
            TabMemoryCache.saveChat(conversationId: conversation.id, messages: toStore)
        }
        .onChange(of: nav.chatComposerPrefill) { _, text in
            guard let text, !text.isEmpty else { return }
            draft = text
            nav.chatComposerPrefill = nil
            AppHaptics.light()
        }
        .onChange(of: nav.mailAttachHandoffs) { _, items in
            guard forcedScope == .mail, !items.isEmpty else { return }
            Task { await ensureMailPendingAttachments() }
        }
        .onAppear {
            if forcedScope == .mail {
                Task { await ensureMailPendingAttachments() }
            } else if let text = nav.chatComposerPrefill, !text.isEmpty {
                draft = text
                nav.chatComposerPrefill = nil
            }
            // Retour depuis Files / preview : recharger si l’état local a été vidé.
            if messages.isEmpty, !isSending {
                chromeById = ConversationSessionStore.chrome(for: conversation.id)
                Task { await loadMessages() }
            }
        }
        // Annuler le stream quand on quitte cette conversation.
        // Prefer onChange(id) over onDisappear: tab switches may remount ChatScreen.
        .onChange(of: conversation.id) { _, _ in
            sendTask?.cancel()
            sendTask = nil
            sendGeneration &+= 1
            isSending = false
            thinkingKind = nil
            hasMoreOlderMessages = false
            isLoadingOlderMessages = false
            scrollAnchorAfterPrepend = nil
            Task { await streamingService.cancel() }
            if forcedScope == .mail, !nav.mailStickyAttachSources.isEmpty {
                Task { await rehydrateMailStickyAttachments() }
            }
        }
        // Ne pas annuler le stream sur changement d’onglet / preview fichier.
        // Arrière-plan : NE PAS cancel (sinon AbortSignal coupe le serveur) —
        // demander du temps CPU/réseau via beginBackgroundTask, puis resync au retour.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, isSending {
                beginChatBackgroundTaskIfNeeded()
            } else if phase == .active {
                let hadBgTask = chatBackgroundTaskId != .invalid
                endChatBackgroundTask()
                if isSending {
                    // Stream encore vivant : ne rien interrompre.
                    return
                }
                // Coupure possible pendant l’absence : récupérer la réponse déjà persistée.
                if hadBgTask || messages.last?.role == "user" {
                    Task {
                        await loadMessages()
                        runtimeStatus = (try? await client.runtimeStatus()) ?? runtimeStatus
                    }
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
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    // VStack (pas LazyVStack) : Lazy sous-estime la hauteur des bulles hors écran
                    // → l’indicateur de scroll saute dès qu’on remonte un peu.
                    VStack(alignment: .leading, spacing: 14) {
                        if hasMoreOlderMessages || isLoadingOlderMessages {
                            HStack {
                                Spacer()
                                if isLoadingOlderMessages {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text("Messages plus anciens")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            .id("history-top")
                        }
                        if messages.isEmpty && streamingText.isEmpty {
                            emptyThread
                        }
                        ForEach(messages) { msg in
                            messageRow(msg)
                        }
                        // Live agent — dans le fil, au-dessus de la réponse (pas du composer).
                        if shouldShowLiveAgentStrip {
                            AgentActivityView(state: agentActivity)
                                .id("agent-live")
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if !streamingText.isEmpty && streamingAssistantId == nil && !awaitingDraftRewrite {
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
                                },
                                onSendFoundFileByMail: { file in
                                    sendFoundFileByMail(file)
                                }
                            )
                            .id("streaming")
                        } else if streamingText.isEmpty && !streamFilesFound.isEmpty && streamingAssistantId == nil {
                            // Plus de bulle « streaming-files » séparée : on matérialise
                            // immédiatement un message assistant pour éviter flash/double carte.
                            Color.clear.frame(height: 0).id("streaming-files-placeholder")
                        } else if isSending,
                                  streamingText.isEmpty,
                                  streamFilesFound.isEmpty,
                                  streamingAssistantId == nil,
                                  !shouldShowLiveAgentStrip,
                                  let thinkingKind {
                            // Indicateur ChatGPT-like dans le fil, à l’emplacement de la réponse.
                            InStreamWorkingIndicator(label: thinkingKind.label)
                                .id("working-indicator")
                        }
                        if draftCardVisible || draftCardStreaming || draftCardSent {
                            MailDraftProposal(
                                draftText: $draftCardText,
                                toText: $draftCardTo,
                                subjectText: $draftCardSubject,
                                draftId: draftCardId,
                                statusLabel: draftCardStatus,
                                isEditing: draftCardEditing,
                                busy: draftCardBusy,
                                isStreaming: draftCardStreaming,
                                isSent: draftCardSent,
                                attachments: draftCardAttachments,
                                recipientSuggestions: draftRecipientSuggestions,
                                candidates: [],
                                onSelectCandidate: { _ in
                                    draftCardCandidates = []
                                    draftRecipientSuggestions = []
                                    Task { await commitDraftHeaders() }
                                },
                                onSelectSuggestion: { _ in
                                    draftCardCandidates = []
                                    draftRecipientSuggestions = []
                                },
                                onRecipientQueryChanged: { query in
                                    scheduleRecipientSuggestions(query: query)
                                },
                                onEditToggle: {
                                    draftCardEditing.toggle()
                                    if draftCardEditing {
                                        // Ne pas requêter avec la liste complète — attendre la frappe.
                                        draftRecipientSuggestions = []
                                    } else {
                                        draftRecipientSuggestions = []
                                    }
                                },
                                onRetry: {
                                    beginDraftImproveFromComposer()
                                },
                                onSend: {
                                    confirmSendDraft = true
                                },
                                onAttach: {
                                    showDocImporter = true
                                },
                                onDismiss: {
                                    dismissDraftCard()
                                },
                                onCommitHeaders: {
                                    Task { await commitDraftHeaders() }
                                }
                            )
                            .id("conversation-draft")
                        }
                        // Spacer viewport : permet d’ancrer le dernier message user en haut
                        // (sinon scrollTo(.top) ne peut pas remonter assez si le fil est court).
                        Color.clear
                            .frame(height: chatBottomScrollSlack)
                            .id("bottom")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Keyboard.dismiss()
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12).onChanged { value in
                        Keyboard.dismiss()
                        // Remontée volontaire → coupe le suivi auto (le bouton n’apparaît qu’assez haut).
                        if value.translation.height > 28 {
                            isPinnedToBottom = false
                        }
                    }
                )
                .onScrollGeometryChange(for: ChatScrollMetrics.self) { geometry in
                    let contentH = geometry.contentSize.height
                    let visibleH = geometry.containerSize.height
                    let offsetY = geometry.contentOffset.y
                    let topInset = geometry.contentInsets.top
                    let bottomInset = geometry.contentInsets.bottom
                    let distanceToBottom = max(0, contentH + bottomInset - visibleH - offsetY)
                    let distanceToTop = max(0, offsetY + topInset)
                    return ChatScrollMetrics(
                        distanceToTop: distanceToTop,
                        distanceToBottom: distanceToBottom,
                        viewportHeight: visibleH
                    )
                } action: { _, metrics in
                    if metrics.viewportHeight > 0, abs(metrics.viewportHeight - scrollViewportHeight) > 1 {
                        scrollViewportHeight = metrics.viewportHeight
                    }
                    // IMPORTANT : pendant le stream, le contenu grandit → distance explose
                    // avant le scrollTo. Ne jamais interpréter ça comme une remontée user.
                    if Date() < suppressScrollGeometryUntil { return }

                    if metrics.distanceToTop < historyLoadOlderOffsetY {
                        Task { await loadOlderMessages(proxy: proxy) }
                    }

                    let distanceToBottom = metrics.distanceToBottom
                    // Pendant la transition clavier + re-stick : ignorer les faux « trop haut ».
                    if stickBottomThroughKeyboard {
                        return
                    }
                    if distanceToBottom > scrollShowButtonThreshold {
                        if isPinnedToBottom { isPinnedToBottom = false }
                        if !showScrollDown {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showScrollDown = true
                            }
                        }
                    } else if distanceToBottom <= scrollHideButtonThreshold {
                        if !isPinnedToBottom { isPinnedToBottom = true }
                        if pinToTopMessageId != nil { pinToTopMessageId = nil }
                        if showScrollDown {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showScrollDown = false
                            }
                        }
                    }
                }
                .onChange(of: keyboardLiftActive) { _, active in
                    guard active, stickBottomThroughKeyboard else { return }
                    // Clavier ouvert + on était déjà en bas → recoller sous le composer.
                    isPinnedToBottom = true
                    showScrollDown = false
                    pinToTopMessageId = nil
                    suppressScrollGeometryUntil = Date().addingTimeInterval(0.7)
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.28)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            guard stickBottomThroughKeyboard else { return }
                            proxy.scrollTo("bottom", anchor: .bottom)
                            stickBottomThroughKeyboard = false
                            isPinnedToBottom = true
                            showScrollDown = false
                        }
                    }
                }
                .onChange(of: floatingChromeHeight) { _, _ in
                    guard keyboardLiftActive, isPinnedToBottom, pinToTopMessageId == nil else { return }
                    suppressScrollGeometryUntil = Date().addingTimeInterval(0.35)
                    DispatchQueue.main.async {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: streamingText) { _, text in
                    guard isPinnedToBottom, !text.isEmpty else { return }
                    scheduleStreamScroll(proxy: proxy)
                }
                .onChange(of: streamScrollTick) { _, _ in
                    guard isPinnedToBottom else { return }
                    scheduleStreamScroll(proxy: proxy)
                }
                .onChange(of: messages.count) { _, _ in
                    // Envoi : pinToTop gère le scroll. Sinon suivi bas seulement si collé.
                    guard pinToTopMessageId == nil, isPinnedToBottom else { return }
                    suppressScrollGeometryUntil = Date().addingTimeInterval(0.35)
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: pinToTopToken) { _, _ in
                    guard let id = pinToTopMessageId else { return }
                    isPinnedToBottom = false
                    suppressScrollGeometryUntil = Date().addingTimeInterval(0.55)
                    // Laisser le layout (spacer + bulle) se poser avant l’ancre .top.
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.35)) {
                            proxy.scrollTo(id, anchor: .top)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                }
                .onChange(of: scrollToken) { _, _ in
                    pinToTopMessageId = nil
                    isPinnedToBottom = true
                    showScrollDown = false
                    suppressScrollGeometryUntil = Date().addingTimeInterval(0.45)
                    withAnimation(.easeOut(duration: 0.35)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: thinkingKind) { _, kind in
                    guard isPinnedToBottom else { return }
                    guard isSending, kind != nil, streamingText.isEmpty, !shouldShowLiveAgentStrip else { return }
                    suppressScrollGeometryUntil = Date().addingTimeInterval(0.3)
                    withAnimation(.easeOut(duration: 0.28)) {
                        proxy.scrollTo("working-indicator", anchor: .bottom)
                    }
                }
                .onChange(of: agentActivity.planSteps) { _, _ in
                    guard isPinnedToBottom, shouldShowLiveAgentStrip else { return }
                    suppressScrollGeometryUntil = Date().addingTimeInterval(0.3)
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo("agent-live", anchor: .bottom)
                    }
                }
                .onChange(of: draftCardText) { _, _ in
                    guard isPinnedToBottom else { return }
                    guard draftInConversation || draftCardStreaming else { return }
                    suppressScrollGeometryUntil = Date().addingTimeInterval(0.25)
                    proxy.scrollTo("conversation-draft", anchor: .bottom)
                }
            }

            if showScrollDown {
                // Au-dessus de l’overlay PJ / Disponible / boutons.
                ScrollToBottomButton {
                    AppHaptics.light()
                    scrollToken += 1
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, composerChromeScrollPadding)
                .transition(.opacity.combined(with: .scale))
                .accessibilitySortPriority(1)
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ msg: MessageDTO) -> some View {
        let chrome = chromeById[msg.id] ?? MessageChromeMeta()
        let liveStreaming = streamingAssistantId == msg.id && isSending
        if let run = chrome.agentRun {
            // Pendant le run : le strip live (timer qui tick) a priorité sur le snapshot chrome figé.
            let hideFrozenChrome = liveStreaming && shouldShowLiveAgentStrip
            if !hideFrozenChrome {
                AgentActivityView(state: run.asActivityState)
                    .id("agent-\(msg.id)")
            }
        }
        MessageBubble(
            message: msg,
            token: session.token,
            baseURL: session.baseURL,
            isEditing: editingMessageId == msg.id,
            sources: chrome.sources,
            mailHandoff: chrome.mailHandoff,
            filesHandoff: chrome.filesHandoff,
            filesFound: chrome.filesFound,
            savedMemories: chrome.savedMemories,
            onOpenMemory: { memory in
                nav.openMemory(memoryId: memory.id)
            },
            onForgetMemory: { memory in
                Task { await forgetSavedMemory(memory, messageId: msg.id) }
            },
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
            },
            onSendFoundFileByMail: { file in
                sendFoundFileByMail(file)
            },
            isLiveStreaming: liveStreaming
        )
        .id(msg.id)
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
                beginDraftImproveFromComposer()
                return
            case .extractTasks:
                showDocImporter = true
                return
            case .searchUnread:
                confirmSendDraft = true
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
            prompt = "Prépare une réponse professionnelle à ce mail et crée un brouillon."
        case .draft:
            prompt = "Crée un nouveau brouillon d’email pour ce contexte."
        case .extractTasks:
            prompt = "Extrais les tâches et dates demandées dans ce mail."
        case .searchUnread:
            prompt = forcedScope == .mail
                ? "Résume mes mails non lus les plus importants."
                : "Liste les fichiers pertinents pour mon contexte actuel."
        case .improve:
            prompt = "Améliore le brouillon en cours pour le rendre plus clair et professionnel."
        }
        await send(forcedText: prompt, hideUserMessage: true)
    }

    /// Active le mode « conseil » : l’utilisateur écrit dans le composer (ex. plus formel).
    private func beginDraftImproveFromComposer() {
        guard draftCardId != nil, !isSending else { return }
        draftCardCollapsed = false
        draftInConversation = true
        draftImprovePending = true
        draft = ""
        persistDraftCardSnapshot()
        AppHaptics.selection()
    }

    /// Réécrit le brouillon ouvert avec une consigne (cachée) → met à jour la carte.
    private func rewriteOpenDraft(instruction: String? = nil) async {
        guard draftCardId != nil, !isSending else { return }
        let text = (instruction?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "Réécris ce brouillon de façon plus claire et naturelle."
        await send(
            forcedText: text,
            hideUserMessage: true,
            rewriteDraftCard: true
        )
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
            if Self.isUserCancellation(error) {
                if let idx = messages.firstIndex(where: { $0.id == summaryId }),
                   messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    messages.remove(at: idx)
                }
                return
            }
            if let idx = messages.firstIndex(where: { $0.id == summaryId }),
               messages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                messages.remove(at: idx)
            }
            self.error = friendlyStreamError(error)
        }
    }

    private func friendlyStreamError(_ error: Error) -> String {
        if case APIClientError.decode = error {
            return "Le résumé est vide — réessaie dans un instant."
        }
        return error.localizedDescription
    }

    private func runMailReplyProduct(threadId: String, instruction: String? = nil) async {
        guard !isSending else { return }
        isSending = true
        error = nil
        thinkingKind = .custom("Préparation de la réponse…")
        draftInConversation = true
        draftCardStreaming = true
        draftCardCollapsed = false
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
            let result = try await client.streamSuggestMailReply(threadId: threadId, instruction: instruction) { token in
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
            draftCardSent = false
            draftInConversation = true
            persistDraftCardSnapshot()
            AppHaptics.success()
            scrollToken += 1
        } catch {
            if Self.isUserCancellation(error) {
                draftInConversation = draftCardId != nil
                return
            }
            draftInConversation = draftCardId != nil
            if case APIClientError.decode = error {
                self.error = "Impossible de préparer la réponse — réessaie."
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    private func applyDraftRecipient(_ email: String) async {
        guard let draftId = draftCardId else { return }
        do {
            try await client.updateEmailDraft(
                id: draftId,
                bodyText: draftCardText,
                to: [email],
                subject: draftCardSubject
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func parseDraftRecipients(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func commitDraftHeaders(preferTo: [String]? = nil) async {
        guard let draftId = draftCardId, !draftCardSent else { return }
        let to = preferTo ?? parseDraftRecipients(draftCardTo)
        do {
            try await client.updateEmailDraft(
                id: draftId,
                bodyText: draftCardText,
                to: to.isEmpty ? nil : to,
                subject: draftCardSubject
            )
            draftRecipientSuggestions = []
            persistDraftCardSnapshot()
            AppHaptics.light()
        } catch {
            self.error = error.localizedDescription
            AppHaptics.warning()
        }
    }

    private func scheduleRecipientSuggestions(query: String) {
        draftRecipientSuggestTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draftCardEditing, !draftCardSent, q.count >= 1 else {
            draftRecipientSuggestions = []
            return
        }
        draftRecipientSuggestTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            do {
                let rows = try await client.suggestMailRecipients(query: q)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    draftRecipientSuggestions = rows
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    draftRecipientSuggestions = []
                }
            }
        }
    }

    private func refreshDraftCardAttachments(draftId: String? = nil) async {
        let id = draftId ?? draftCardId
        guard let id, !id.isEmpty else { return }
        do {
            let detail = try await client.fetchEmailDraft(id: id)
            draftCardAttachments = detail.attachments
            if draftCardTo.isEmpty {
                draftCardTo = detail.to.joined(separator: ", ")
            }
            if draftCardSubject.isEmpty {
                draftCardSubject = detail.subject
            }
            if draftCardText.isEmpty {
                draftCardText = detail.bodyText
            }
        } catch {
            // Affichage best-effort — le brouillon reste utilisable sans liste PJ.
        }
    }

    /// Brouillon ouvert + IDs chat → fusionne les PJ sur CE brouillon (chemin produit, pas le LLM).
    @discardableResult
    private func syncAttachmentsToOpenDraft(_ attachmentIds: [String]) async -> Bool {
        let ids = attachmentIds.filter { !$0.isEmpty && !$0.hasPrefix("local-") }
        guard let draftId = draftCardId, !draftId.isEmpty, !ids.isEmpty, !draftCardSent else {
            return false
        }
        do {
            try await client.attachFilesToEmailDraft(id: draftId, attachmentIds: ids)
            await refreshDraftCardAttachments(draftId: draftId)
            draftCardCollapsed = false
            draftInConversation = true
            AppHaptics.success()
            return true
        } catch {
            AppHaptics.warning()
            return false
        }
    }

    private func persistActiveConversation() {
        let scope = forcedScope ?? .general
        let key: String? = {
            if scope == .general { return nil }
            if let override = persistenceKeyOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
               !override.isEmpty {
                return override
            }
            // Folder context: prefer folder:rootId:path over global.
            if let rootId = forcedActiveContext?.rootId, !rootId.isEmpty {
                let path = forcedActiveContext?.label ?? ""
                // label may be title — still better than __global__ for root-level folders.
                if forcedActiveContext?.fileId == nil {
                    return "folder:\(rootId):\(path)"
                }
            }
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

    /// Ferme la sheet assistant (Mail/Files) tout en gardant la conversation en store.
    private func dismissAssistantKeepingContext() {
        persistActiveConversation()
        Keyboard.dismiss()
        // Token global : ferme les sheets locales Files/Mail même si `dismiss` est un no-op.
        nav.dismissAssistantSheets()
        if let onRequestClose {
            onRequestClose()
        } else if forcedScope != nil {
            dismiss()
        }
    }

    private func openFoundFilePreview(_ file: FilesFoundFileDTO) {
        persistActiveConversation()
        Keyboard.dismiss()
        nav.dismissAssistantSheets()
        onRequestClose?()
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
        Keyboard.dismiss()
        nav.dismissAssistantSheets()
        onRequestClose?()
        let parent = FilesPathHelpers.parentFolder(of: file.relativePath)
        nav.openFileFolder(
            rootId: file.rootId,
            folderPath: parent,
            title: FilesPathHelpers.lastSegment(of: parent).isEmpty
                ? nil
                : FilesPathHelpers.lastSegment(of: parent)
        )
    }

    private func sendFoundFileByMail(_ file: FilesFoundFileDTO) {
        persistActiveConversation()
        Keyboard.dismiss()
        onRequestClose?()
        nav.shareFilesToMail(files: [(fileId: file.id, filename: file.filename)])
        AppHaptics.light()
    }

    /// Handoffs frais et/ou sources sticky (après « Nouveau chat »).
    private func ensureMailPendingAttachments() async {
        guard forcedScope == .mail else { return }
        if !nav.mailAttachHandoffs.isEmpty {
            await consumeMailAttachHandoffs()
            return
        }
        if pendingAttachments.isEmpty, !nav.mailStickyAttachSources.isEmpty {
            await rehydrateMailStickyAttachments()
        }
    }

    private func consumeMailAttachHandoffs() async {
        guard forcedScope == .mail else { return }
        let items = nav.mailAttachHandoffs
        guard !items.isEmpty else { return }
        nav.mailAttachHandoffs = []
        // Handoff Files → Mail : PJ seulement, jamais de texte prérempli.
        nav.mailComposerPrefill = nil
        for item in items {
            if !nav.mailStickyAttachSources.contains(where: { $0.fileId == item.fileId }) {
                nav.mailStickyAttachSources.append(item)
            }
            if pendingAttachments.contains(where: { $0.sourceFileId == item.fileId }) {
                continue
            }
            await attachFilesEntryToComposer(fileId: item.fileId, filename: item.filename)
        }
        AppHaptics.success()
    }

    /// Ré-attache les sources Files sur la conversation courante (IDs PJ liés à la conv).
    private func rehydrateMailStickyAttachments() async {
        guard forcedScope == .mail else { return }
        let sources = nav.mailStickyAttachSources
        guard !sources.isEmpty else { return }
        pendingAttachments.removeAll {
            $0.sourceFileId != nil || $0.id.hasPrefix("local-mail-")
        }
        for item in sources {
            await attachFilesEntryToComposer(fileId: item.fileId, filename: item.filename)
        }
        AppHaptics.light()
    }

    private func attachFilesEntryToComposer(fileId: String, filename: String) async {
        let tempId = "local-mail-\(UUID().uuidString)"
        pendingAttachments.append(
            UploadedAttachment(
                id: tempId,
                filename: filename,
                mimeType: "application/octet-stream",
                sizeBytes: 0,
                isUploading: true,
                sourceFileId: fileId
            )
        )
        do {
            let (data, resolvedName, mime) = try await client.downloadFileBytes(fileId: fileId)
            var uploaded = try await client.uploadAttachment(
                conversationId: conversation.id,
                filename: resolvedName.isEmpty ? filename : resolvedName,
                mimeType: mime,
                fileData: data
            )
            uploaded.sourceFileId = fileId
            if let idx = pendingAttachments.firstIndex(where: { $0.id == tempId }) {
                pendingAttachments[idx] = uploaded
            } else {
                pendingAttachments.append(uploaded)
            }
            await syncAttachmentsToOpenDraft([uploaded.id])
        } catch {
            pendingAttachments.removeAll { $0.id == tempId }
            self.error = error.localizedDescription
            AppHaptics.warning()
        }
    }

    private func downloadFoundFile(_ file: FilesFoundFileDTO) async {
        do {
            let content = try await client.fetchFileContent(fileId: file.id)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(file.filename)
            if let binary = content.binary, !binary.isEmpty {
                try binary.write(to: tmp, options: .atomic)
            } else if let text = content.text, !text.isEmpty {
                try Data(text.utf8).write(to: tmp, options: .atomic)
            } else {
                throw APIClientError.decode
            }
            // Partager AVANT de fermer le chat — sinon le share n’a plus de presentateur.
            NativeShare.present(url: tmp, title: file.filename)
            AppHaptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendDraftCard() async {
        guard let draftId = draftCardId, !draftCardSent else { return }
        draftCardBusy = true
        defer { draftCardBusy = false }
        do {
            let body = draftCardText.trimmingCharacters(in: .whitespacesAndNewlines)
            let to = parseDraftRecipients(draftCardTo)
            try await client.updateEmailDraft(
                id: draftId,
                bodyText: body,
                to: to.isEmpty ? nil : to,
                subject: draftCardSubject
            )
            try await client.validateEmailDraft(id: draftId)
            let proposal = try await client.proposeEmailSend(draftId: draftId)
            try await client.confirmEmailSend(
                actionId: proposal.actionId,
                confirmationToken: proposal.confirmationToken,
                conversationId: conversation.id
            )
            // Carte → reçu vert ; PJ composer retirées.
            pendingAttachments = []
            if forcedScope == .mail {
                nav.clearMailStickyAttachments()
            }
            draftCardSent = true
            draftCardStatus = "Envoyé"
            draftCardEditing = false
            draftCardStreaming = false
            draftCardCollapsed = false
            draftCardCandidates = []
            draftCardAttachments = []
            draftRecipientSuggestions = []
            draftInConversation = true
            awaitingDraftRewrite = false
            draftPreviewReceivedThisTurn = false
            persistDraftCardSnapshot()
            AppHaptics.success()
        } catch {
            self.error = error.localizedDescription
            AppHaptics.warning()
        }
    }

    /// Croix : masque la carte du fil — brouillon conservé localement + serveur, récupérable.
    private func dismissDraftCard() {
        guard !draftCardSent else { return }
        draftCardCollapsed = true
        draftCardEditing = false
        draftImprovePending = false
        draftRecipientSuggestTask?.cancel()
        draftRecipientSuggestions = []
        persistDraftCardSnapshot()
        AppHaptics.light()
    }

    private func recoverDraftCard() {
        draftCardCollapsed = false
        draftInConversation = true
        persistDraftCardSnapshot()
        AppHaptics.light()
        // Remonter vers la carte une fois rétablie.
        scrollToken += 1
    }

    private func persistDraftCardSnapshot() {
        guard draftInConversation || draftCardId != nil || draftCardSent || draftCardStreaming else {
            ConversationSessionStore.clearDraftCard(conversationId: conversation.id)
            return
        }
        ConversationSessionStore.saveDraftCard(
            conversationId: conversation.id,
            .init(
                draftId: draftCardId,
                text: draftCardText,
                to: draftCardTo,
                subject: draftCardSubject,
                status: draftCardStatus,
                sent: draftCardSent,
                inConversation: true,
                collapsed: draftCardCollapsed && !draftCardSent
            )
        )
    }

    private func restoreDraftCardSnapshot() {
        guard let snap = ConversationSessionStore.draftCard(conversationId: conversation.id) else { return }
        // Ne pas écraser un brouillon déjà hydraté dans cette session.
        guard draftCardId == nil, !draftCardStreaming, !draftCardSent else { return }
        draftCardId = snap.draftId
        draftCardText = snap.text
        draftCardTo = snap.to
        draftCardSubject = snap.subject
        draftCardStatus = snap.status
        draftCardSent = snap.sent
        draftCardCollapsed = snap.collapsed && !snap.sent
        draftInConversation = snap.inConversation || snap.sent || snap.draftId != nil
        draftCardEditing = false
        if let id = snap.draftId, !id.isEmpty {
            Task { await refreshDraftCardAttachments(draftId: id) }
        }
    }

    /// Réhydrate la carte depuis le serveur si absente en local (kill app / autre device).
    private func restoreDraftCardFromServerIfNeeded() async {
        guard draftCardId == nil, !draftCardStreaming, !draftCardSent else {
            if let id = draftCardId, !id.isEmpty {
                await refreshDraftCardAttachments(draftId: id)
            }
            return
        }
        do {
            guard let detail = try await client.fetchActiveEmailDraft(conversationId: conversation.id) else {
                return
            }
            draftCardId = detail.draftId
            draftCardText = detail.bodyText
            draftCardTo = detail.to.joined(separator: ", ")
            draftCardSubject = detail.subject
            draftCardAttachments = detail.attachments
            draftCardStatus = "Brouillon"
            draftCardSent = false
            draftInConversation = true
            draftCardEditing = false
            persistDraftCardSnapshot()
        } catch {
            // Silencieux : pas de brouillon / email off.
        }
    }

    /// Anciens messages où les consignes outil ont fuité dans le contenu user.
    private static func isLeakedDraftControlMessage(_ content: String) -> Bool {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        let markers = [
            "Brouillon email ouvert",
            "Demande de l’utilisateur:",
            "Demande de l'utilisateur:",
            "Appelle immédiatement",
            "email_create_draft",
            "INTERDIT d",
            "INTERDIT d’écrire le corps",
            "INTERDIT d'écrire le corps",
            "la carte brouillon l’affiche",
            "la carte brouillon l'affiche",
            "RÉÉCRITURE :",
            "Réécris le corps de CE brouillon",
            "Réécris UNIQUEMENT le corps",
            "draftId=",
            "Corps actuel:",
            "Destinataire:",
            "outil email_create_draft",
            "N’invente PAS d’autre contenu",
            "N'invente PAS d'autre contenu",
        ]
        let hitCount = markers.reduce(0) { count, marker in
            text.localizedCaseInsensitiveContains(marker) ? count + 1 : count
        }
        // Assez de marqueurs → litanie outil, pas un vrai message user.
        if hitCount >= 2 { return true }
        if text.localizedCaseInsensitiveContains("draftId=")
            && text.localizedCaseInsensitiveContains("INTERDIT") {
            return true
        }
        if text.localizedCaseInsensitiveContains("Brouillon email ouvert")
            && text.localizedCaseInsensitiveContains("Demande de") {
            return true
        }
        return false
    }

    private static func withoutLeakedDraftControlMessages(_ list: [MessageDTO]) -> [MessageDTO] {
        list.filter { msg in
            if msg.role == "user", isLeakedDraftControlMessage(msg.content) {
                return false
            }
            return true
        }
    }

    /// Après « Améliorer » : seule une vraie carte `draft_preview` (outil) met à jour le brouillon.
    /// Ne JAMAIS PATCH-er avec le texte streamé — c’était la cause des corps absurdes
    /// (échecs d’outils, listes de mails, etc. collés dans le brouillon).
    private func finishDraftRewriteIfNeeded(appliedViaPreview: Bool, fallbackText: String) async {
        guard awaitingDraftRewrite else { return }
        defer {
            awaitingDraftRewrite = false
            draftCardStreaming = false
            draftCardStatus = "Brouillon"
            suppressAssistantNarration = false
        }
        if appliedViaPreview {
            AppHaptics.success()
            return
        }
        _ = fallbackText
        // Corps inchangé ; prévenir l’utilisateur plutôt que d’écraser avec de la narration.
        error = "L’amélioration n’a pas pu mettre à jour le brouillon. Réessaie avec une consigne plus précise."
        AppHaptics.warning()
    }

    /// Message API pour une réécriture (le fil affiche seulement la consigne courte).
    private static func draftRewriteApiMessage(
        instruction: String,
        body: String,
        to: String,
        subject: String
    ) -> String {
        let clippedBody = String(body.prefix(8000))
        let toLine = to.trimmingCharacters(in: .whitespacesAndNewlines)
        let subjectLine = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        return """
Réécris UNIQUEMENT le corps de CE brouillon email selon la consigne. Appelle immédiatement email_create_draft (le brouillon est déjà ouvert dans le contexte — conserve destinataires/objet sauf demande contraire). N’écris PAS le corps dans le chat. N’invente PAS d’autre contenu (pas de listes, pas de statut d’outils).

Consigne: \(instruction)
Destinataire: \(toLine.isEmpty ? "(inchangé)" : toLine)
Objet: \(subjectLine.isEmpty ? "(inchangé)" : subjectLine)
Corps actuel:
\(clippedBody)
"""
    }

    /// Hauteur du fade viewport (bas physique), indépendante du contenu scrollé.
    private static let bottomFadeHeight: CGFloat = 420

    /// Hauteur réservée en bas du fil pour le chrome flottant.
    private var composerChromeScrollPadding: CGFloat {
        max(floatingChromeHeight, 140) + 8
    }

    /// Slack sous le fil : assez grand pour que `scrollTo(userId, .top)` place
    /// le message envoyé en haut du viewport (sinon le contenu est trop court).
    private var chatBottomScrollSlack: CGFloat {
        let chrome = composerChromeScrollPadding
        let needsPinRoom = pinToTopMessageId != nil || isSending
        guard needsPinRoom, scrollViewportHeight > 80 else { return chrome }
        return max(chrome, scrollViewportHeight - 12)
    }

    /// Ancre le message user en haut après un envoi (coupe le suivi bas/stream).
    private func requestPinMessageToTop(_ messageId: String) {
        pinToTopMessageId = messageId
        pinToTopToken += 1
        isPinnedToBottom = false
    }

    /// Carte brouillon visible dans le fil (pas masquée, pas seulement envoyée).
    private var draftCardVisible: Bool {
        !draftCardCollapsed
            && !draftCardSent
            && (draftInConversation || draftCardId != nil || draftCardStreaming)
    }

    /// Brouillon masqué par la croix — récupérable sans être affiché dans le fil.
    private var draftCardRecoverable: Bool {
        draftCardCollapsed && !draftCardSent && draftCardId != nil
    }

    /// Lift depuis le bas physique (ZStack ignore déjà la safe area container).
    /// Un seul offset — au-dessus des labels Chat/Mail/Files (pas collé, pas trop haut).
    /// Ne pas rajouter `bottomSafeInset` (sinon double lift).
    private var tabBarOverlayLift: CGFloat {
        if keyboardLiftActive { return AppTheme.space8 }
        return 112
    }

    /// Composer + chrome : calque au-dessus du fade (pas d’arrière-plan de bande opaque).
    @ViewBuilder
    private var composerFloatingChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            }
            if let memoryNotice {
                MemorySavedNotice(text: memoryNotice) {
                    self.memoryNotice = nil
                    nav.openMemory()
                }
                .padding(.horizontal, 14)
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
            }
            if let banner = ServiceStatusBanner.chatContext(infra: infra, onRepair: { serviceId in
                Task { await infra.repairService(id: serviceId) }
            }) {
                banner
                    .padding(.horizontal, AppTheme.space12)
            }

            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(pendingAttachments) { att in
                            PendingAttachmentCard(attachment: att) {
                                Task { await removePending(att) }
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.space14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if draftCardRecoverable {
                Button {
                    recoverDraftCard()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.badge")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Récupérer le brouillon")
                            .font(CNFont.caption.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(AppTheme.mailAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(AppTheme.mailAccent.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(AppTheme.mailAccent.opacity(0.28), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppTheme.space14)
                .accessibilityLabel("Récupérer le brouillon")
            }

            VStack(alignment: .leading, spacing: 8) {
                if !isSending {
                    HStack(spacing: 8) {
                        RuntimeStatusPill(status: displayRuntimeStatus)
                        if !assistantReadyForSend {
                            Text(sendBlockedHint)
                                .font(CNFont.caption2)
                                .foregroundStyle(AppTheme.mutedForeground)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        ComposerQuickControls(
                            thinkingEnabled: isThinkingEnabled,
                            chatMode: chatMode,
                            toolChannel: toolChannel,
                            thinkingAvailable: thinkingToggleAvailable,
                            showsToolChannel: showsToolChannelPicker,
                            onToggleThinking: { toggleThinking() },
                            onToggleMode: {
                                applyMode(chatMode == "agent" ? "chat" : "agent")
                            },
                            onCycleTool: { cycleToolChannel() }
                        )
                    }
                    .padding(.horizontal, AppTheme.space16)
                }

                composer
            }
            .padding(.bottom, tabBarOverlayLift)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { _, height in
            guard height > 1, abs(height - floatingChromeHeight) > 0.5 else { return }
            floatingChromeHeight = height
        }
        .allowsHitTesting(true)
    }

    private func updateBottomSafeInset(_ inset: CGFloat) {
        // Tab bar + home indicator ≈ 49–110 ; clavier typiquement > 200.
        if inset > 0 && inset < 140 {
            bottomSafeInset = inset
            if keyboardLiftActive {
                keyboardLiftActive = false
                stickBottomThroughKeyboard = false
            }
        } else if inset >= 140 {
            if !keyboardLiftActive {
                // Capturer AVANT que la géométrie ne croie qu’on a remonté.
                stickBottomThroughKeyboard =
                    isPinnedToBottom && pinToTopMessageId == nil
            }
            keyboardLiftActive = true
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if draftImprovePending, draftCardId != nil {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.mailAccent)
                    Text("Amélioration du brouillon — décris ce que tu veux changer")
                        .font(CNFont.caption.weight(.medium))
                        .foregroundStyle(AppTheme.foreground)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button {
                        draftImprovePending = false
                        AppHaptics.light()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(AppTheme.mutedForeground)
                            .frame(width: 28, height: 28)
                            .background(AppTheme.surfaceElevated.opacity(0.7), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Annuler l’amélioration")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.mailAccent.opacity(0.12), in: Capsule())
                .padding(.horizontal, AppTheme.space12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            ComposerCapsule(
                draft: $draft,
                photoItem: $photoItem,
                showTools: $showTools,
                placeholder: {
                    if draftImprovePending {
                        return "Ex. plus formel, ajoute cette info…"
                    }
                    if editingMessageId != nil {
                        return "Modifier le message…"
                    }
                    return "Message"
                }(),
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
                thinkingEnabled: isThinkingEnabled,
                thinkingAvailable: thinkingToggleAvailable,
                toolChannel: toolChannel,
                showsToolChannelPicker: showsToolChannelPicker,
                onModeChange: { mode in applyMode(mode) },
                onWebChange: { enabled in applyWeb(enabled) },
                onModelChange: { modelId in Task { await applyModel(modelId) } },
                onReasoningChange: { mode in applyReasoning(mode) },
                onToggleThinking: { toggleThinking() },
                onSelectToolChannel: { channel in selectToolChannel(channel) },
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
            .padding(.bottom, AppTheme.space4)
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

    private var toolChannel: ComposerToolChannel {
        // Assistants contextuels : canal imposé (pas de pastille de choix).
        switch forcedScope {
        case .mail: return .email
        case .files: return .files
        default: return ComposerToolChannel(rawValue: toolChannelRaw) ?? .web
        }
    }

    private var showsToolChannelPicker: Bool {
        forcedScope == nil
    }

    private var isThinkingEnabled: Bool {
        let e = reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !e.isEmpty && e != "off" && e != "none"
    }

    private var thinkingToggleAvailable: Bool {
        !reasoningModes.isEmpty || !reasoningEffort.isEmpty
    }

    private var thinkingOffModeId: String {
        if let off = reasoningModes.first(where: {
            let id = $0.id.lowercased()
            return id == "off" || id == "none"
        }) {
            return off.id
        }
        return "off"
    }

    private var thinkingOnModeId: String {
        if let on = reasoningModes.first(where: {
            let id = $0.id.lowercased()
            return id != "off" && id != "none"
        }) {
            return on.id
        }
        return reasoningModes.first?.id ?? "medium"
    }

    private func toggleThinking() {
        if isThinkingEnabled {
            applyReasoning(thinkingOffModeId)
        } else {
            applyReasoning(thinkingOnModeId)
        }
    }

    private func cycleToolChannel() {
        guard showsToolChannelPicker else { return }
        var next = toolChannel
        next.cycle()
        toolChannelRaw = next.rawValue
        // Aligne le réglage web global avec le canal choisi.
        applyWeb(next == .web)
    }
    private func selectToolChannel(_ channel: ComposerToolChannel) {
        guard showsToolChannelPicker else { return }
        toolChannelRaw = channel.rawValue
        applyWeb(channel == .web)
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
        WidgetSharedStore.publishAssistant(
            status: runtimeStatus,
            modelName: selectedModel.isEmpty ? snap.loadedModel : selectedModel,
            conversationTitle: conversationTitle.isEmpty ? conversation.title : conversationTitle
        )
    }

    private func loadMessages(preserveAssistantId: String? = nil) async {
        do {
            let page = try await client.listMessages(
                conversationId: conversation.id,
                limit: historyInitialPageSize
            )
            let recent = page.messages
            // Conserve les pages plus anciennes déjà chargées (scroll haut).
            var olderKept: [MessageDTO] = []
            if let firstRecentId = recent.first?.id,
               let cut = messages.firstIndex(where: { $0.id == firstRecentId }) {
                olderKept = Array(messages.prefix(cut))
            }
            let combined = olderKept + recent
            messages = Self.withoutLeakedDraftControlMessages(
                mergeMessages(
                    local: messages,
                    server: combined,
                    preserveAssistantId: preserveAssistantId
                )
            )
            if olderKept.isEmpty {
                hasMoreOlderMessages = page.hasMore
            }
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
            chromeById = ConversationSessionStore.reattachOrphanFilesFound(
                conversationId: conversation.id,
                messages: messages
            )
            // Réhydrate les pastilles web_N depuis l’API (survit au changement de chat / restart).
            hydrateChromeSources(from: messages)
            pruneChromeOutsideWindow()
            error = nil
            let ids = messages.flatMap { $0.attachments ?? [] }
                .filter { ($0.mimeType ?? "").hasPrefix("image/") || $0.type == "image" }
                .map(\.id)
            client.prefetchAttachmentThumbs(ids: ids, maxPixelSize: 360)
            contextSnapshot = try? await client.conversationContext(conversationId: conversation.id)
            // Ne pas écraser un pin « message user en haut » juste après envoi.
            if pinToTopMessageId == nil {
                scrollToken += 1
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Charge une page plus ancienne (scroll vers le haut) sans dégrader le contenu visible.
    private func loadOlderMessages(proxy: ScrollViewProxy) async {
        guard hasMoreOlderMessages, !isLoadingOlderMessages, !isSending else { return }
        guard let oldestId = messages.first?.id else { return }
        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }
        do {
            let page = try await client.listMessages(
                conversationId: conversation.id,
                limit: historyOlderPageSize,
                beforeId: oldestId
            )
            let older = page.messages.filter { candidate in
                !messages.contains(where: { $0.id == candidate.id })
            }
            hasMoreOlderMessages = page.hasMore
            guard !older.isEmpty else {
                // Doublons / pivot invalide : stoppe les retries inutiles.
                if !page.hasMore || page.messages.isEmpty {
                    hasMoreOlderMessages = false
                }
                return
            }
            suppressScrollGeometryUntil = Date().addingTimeInterval(0.45)
            scrollAnchorAfterPrepend = oldestId
            messages = Self.withoutLeakedDraftControlMessages(older + messages)
            hydrateChromeSources(from: older)
            pruneChromeOutsideWindow()
            let ids = older.flatMap { $0.attachments ?? [] }
                .filter { ($0.mimeType ?? "").hasPrefix("image/") || $0.type == "image" }
                .map(\.id)
            client.prefetchAttachmentThumbs(ids: ids, maxPixelSize: 360)
            if let anchor = scrollAnchorAfterPrepend {
                // Restaure la position visuelle après prepend.
                proxy.scrollTo(anchor, anchor: .top)
                scrollAnchorAfterPrepend = nil
            }
        } catch {
            // Silencieux : le fil récent reste utilisable.
            #if DEBUG
            print("[chat] loadOlderMessages: \(error.localizedDescription)")
            #endif
        }
    }

    private func pruneChromeOutsideWindow() {
        var keep = Set(messages.map(\.id))
        if let streamingAssistantId {
            keep.insert(streamingAssistantId)
        }
        chromeById = chromeById.filter { keep.contains($0.key) }
        ConversationSessionStore.replaceChrome(conversationId: conversation.id, chrome: chromeById)
    }

    /// Attache les `sources` renvoyées par GET /messages au chrome (pastilles web_N).
    /// Ne remplace pas un chrome déjà rempli (ex. stream en cours / session mémoire).
    private func hydrateChromeSources(from msgs: [MessageDTO]) {
        var changed = false
        for msg in msgs {
            guard let sources = msg.sources, !sources.isEmpty else { continue }
            var chrome = chromeById[msg.id] ?? MessageChromeMeta()
            if chrome.sources.isEmpty {
                chrome.sources = sources
                chromeById[msg.id] = chrome
                changed = true
            }
        }
        if changed {
            ConversationSessionStore.replaceChrome(conversationId: conversation.id, chrome: chromeById)
        }
    }

    /// Fusionne serveur + local pour éviter un frame vide pendant/après le stream.
    private func mergeMessages(
        local: [MessageDTO],
        server: [MessageDTO],
        preserveAssistantId: String?
    ) -> [MessageDTO] {
        if server.isEmpty { return local }
        var byId = Dictionary(server.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        // Conserver le contenu local plus long si le serveur est encore en retard
        for msg in local where msg.role == "assistant" {
            if let existing = byId[msg.id], existing.content.count < msg.content.count {
                byId[msg.id] = MessageDTO(
                    id: msg.id,
                    role: msg.role,
                    content: msg.content,
                    createdAt: existing.createdAt ?? msg.createdAt,
                    attachments: existing.attachments ?? msg.attachments,
                    sources: existing.sources ?? msg.sources
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

    /// Évite une double bulle assistant après promote + reload serveur (IDs différents, même contenu).
    private func dedupeTrailingAssistant(matching content: String, preferId: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            // Même fichiers trouvés sans texte : fusionne chrome + drop orphan asst-*
            if messages.count >= 2 {
                let lastTwo = messages.suffix(2)
                if lastTwo.allSatisfy({ $0.role == "assistant" }) {
                    let ids = lastTwo.map(\.id)
                    if let drop = ids.first(where: { $0 != preferId && $0.hasPrefix("asst-") }) {
                        messages.removeAll { $0.id == drop }
                        chromeById.removeValue(forKey: drop)
                    }
                }
            }
            return
        }
        var seenContent = false
        var keep: [MessageDTO] = []
        for msg in messages {
            if msg.role == "assistant",
               msg.content.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
                if seenContent {
                    if msg.id != preferId {
                        chromeById.removeValue(forKey: msg.id)
                        continue
                    }
                }
                seenContent = true
            }
            keep.append(msg)
        }
        messages = keep
    }

    /// Fusionne un message local `asst-*` (souvent créé par files_found) vers l’ID serveur.
    private func remountStreamingAssistant(onto serverId: String) {
        let previousId = streamingAssistantId
        streamingAssistantId = serverId

        if let previousId, previousId != serverId,
           let idx = messages.firstIndex(where: { $0.id == previousId }) {
            let old = messages[idx]
            let oldChrome = chromeById[previousId] ?? MessageChromeMeta()
            if let existingIdx = messages.firstIndex(where: { $0.id == serverId }) {
                let existing = messages[existingIdx]
                let mergedContent = existing.content.count >= old.content.count
                    ? existing.content
                    : old.content
                messages[existingIdx] = MessageDTO(
                    id: serverId,
                    role: "assistant",
                    content: mergedContent,
                    createdAt: existing.createdAt ?? old.createdAt,
                    attachments: existing.attachments ?? old.attachments
                )
                messages.remove(at: idx)
            } else {
                messages[idx] = MessageDTO(
                    id: serverId,
                    role: "assistant",
                    content: old.content,
                    createdAt: old.createdAt,
                    attachments: old.attachments
                )
            }
            var merged = chromeById[serverId] ?? MessageChromeMeta()
            if merged.sources.isEmpty { merged.sources = oldChrome.sources }
            if merged.mailHandoff == nil { merged.mailHandoff = oldChrome.mailHandoff }
            if merged.filesHandoff == nil { merged.filesHandoff = oldChrome.filesHandoff }
            if merged.agentRun == nil { merged.agentRun = oldChrome.agentRun }
            if merged.savedMemories.isEmpty { merged.savedMemories = oldChrome.savedMemories }
            else if !oldChrome.savedMemories.isEmpty {
                var byId = Dictionary(uniqueKeysWithValues: merged.savedMemories.map { ($0.id, $0) })
                for item in oldChrome.savedMemories where byId[item.id] == nil { byId[item.id] = item }
                merged.savedMemories = Array(byId.values)
            }
            if merged.filesFound.isEmpty { merged.filesFound = oldChrome.filesFound }
            else if !oldChrome.filesFound.isEmpty {
                merged.filesFound = mergeFilesFound(merged.filesFound, oldChrome.filesFound)
            }
            chromeById[serverId] = merged
            chromeById.removeValue(forKey: previousId)
            ConversationSessionStore.setChrome(
                merged,
                conversationId: conversation.id,
                messageId: serverId
            )
            // Tokens déjà accumulés dans streamingText → basculer sur le message serveur.
            if !streamingText.isEmpty,
               let sIdx = messages.firstIndex(where: { $0.id == serverId }),
               messages[sIdx].content.isEmpty {
                messages[sIdx] = MessageDTO(
                    id: serverId,
                    role: "assistant",
                    content: streamingText,
                    createdAt: messages[sIdx].createdAt,
                    attachments: messages[sIdx].attachments
                )
            }
            return
        }

        if messages.firstIndex(where: { $0.id == serverId }) == nil {
            messages.append(
                MessageDTO(id: serverId, role: "assistant", content: streamingText, createdAt: nil)
            )
        }
    }

    /// Ancre unique pour les cartes fichiers de ce tour.
    private func ensureSingleFilesFoundAnchor(for files: [FilesFoundFileDTO]) -> String {
        let ids = Set(files.map(\.id))
        // 1) Déjà sur le message stream courant
        if let current = streamingAssistantId,
           messages.contains(where: { $0.id == current }) {
            return current
        }
        // 2) Un message existant affiche déjà ces fichiers
        for msg in messages.reversed() where msg.role == "assistant" {
            let found = Set((chromeById[msg.id]?.filesFound ?? []).map(\.id))
            if !found.isDisjoint(with: ids) {
                return msg.id
            }
        }
        // 3) Dernier assistant vide / local de ce tour
        if let last = messages.last(where: { $0.role == "assistant" }),
           last.id.hasPrefix("asst-") || last.content.isEmpty {
            return last.id
        }
        // 4) Nouvelle ancre
        let id = "asst-\(UUID().uuidString)"
        messages.append(MessageDTO(id: id, role: "assistant", content: "", createdAt: nil))
        return id
    }

    private func mergeFilesFound(
        _ existing: [FilesFoundFileDTO],
        _ incoming: [FilesFoundFileDTO]
    ) -> [FilesFoundFileDTO] {
        var seen = Set<String>()
        var out: [FilesFoundFileDTO] = []
        for f in existing + incoming {
            if seen.insert(f.id).inserted {
                out.append(f)
            }
        }
        return out
    }

    /// Une seule carte par fichier — supprime les bulles assistant en double.
    private func dedupeAssistantMessagesSharing(fileIds: Set<String>, keepId: String) {
        guard !fileIds.isEmpty else { return }
        var dropIds: [String] = []
        for msg in messages where msg.role == "assistant" && msg.id != keepId {
            let found = Set((chromeById[msg.id]?.filesFound ?? []).map(\.id))
            if !found.isDisjoint(with: fileIds) {
                // Transférer le texte utile vers keepId si besoin.
                if let keepIdx = messages.firstIndex(where: { $0.id == keepId }),
                   let dropIdx = messages.firstIndex(where: { $0.id == msg.id }) {
                    let keep = messages[keepIdx]
                    let drop = messages[dropIdx]
                    if keep.content.count < drop.content.count {
                        messages[keepIdx] = MessageDTO(
                            id: keep.id,
                            role: keep.role,
                            content: drop.content,
                            createdAt: keep.createdAt ?? drop.createdAt,
                            attachments: keep.attachments ?? drop.attachments
                        )
                    }
                }
                dropIds.append(msg.id)
            }
        }
        if !dropIds.isEmpty {
            messages.removeAll { dropIds.contains($0.id) }
            for id in dropIds {
                chromeById.removeValue(forKey: id)
            }
        }
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
            await syncAttachmentsToOpenDraft([uploaded.id])
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
                // Brouillon mail ouvert : rattacher la PJ au brouillon (pas seulement au chat).
                await syncAttachmentsToOpenDraft([uploaded.id])
            } catch {
                pendingAttachments.removeAll { $0.id == tempId }
                self.error = error.localizedDescription
            }
        }
    }

    private func removePending(_ att: UploadedAttachment) async {
        pendingAttachments.removeAll { $0.id == att.id }
        if let sourceId = att.sourceFileId {
            nav.mailStickyAttachSources.removeAll { $0.fileId == sourceId }
        }
        if !att.id.hasPrefix("local-") {
            try? await client.deleteAttachment(id: att.id)
        }
    }

    private func forgetSavedMemory(_ memory: SavedMemoryChipDTO, messageId: String) async {
        do {
            let client = APIClient(baseURL: session.baseURL, token: session.token)
            try await client.deleteMemory(id: memory.id)
            var chrome = chromeById[messageId] ?? MessageChromeMeta()
            chrome.savedMemories.removeAll { $0.id == memory.id }
            chromeById[messageId] = chrome
            ConversationSessionStore.setChrome(
                chrome,
                conversationId: conversation.id,
                messageId: messageId
            )
            AppHaptics.light()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Détecte une demande de réponse au fil mail actif (texte libre).
    private func isMailReplyIntent(_ text: String) -> Bool {
        let lower = text.lowercased()
        let keys = ["répond", "repond", "reply", "rédige une réponse", "redige une reponse", "écris une réponse", "ecris une reponse", "prépare une réponse", "prepare une reponse"]
        return keys.contains { lower.contains($0) }
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

    private func send(options: ChatSendOptions? = nil, forcedText: String? = nil, hideUserMessage: Bool = false, rewriteDraftCard: Bool = false) async {
        guard !isSending else { return }
        let rawText = (forcedText ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = pendingAttachments.filter { !$0.isUploading && !$0.id.hasPrefix("local-") }.map(\.id)
        let isEdit = editingMessageId != nil
        guard !rawText.isEmpty || !ids.isEmpty || options?.regenerate == true else { return }

        // Réponse au fil mail : API produit (contexte thread garanti), pas un brouillon orphelin.
        if !rewriteDraftCard,
           options?.regenerate != true,
           editingMessageId == nil,
           let threadId = forcedActiveContext?.mailThreadId,
           !threadId.isEmpty,
           isMailReplyIntent(rawText) {
            await runMailReplyProduct(threadId: threadId, instruction: rawText)
            return
        }

        // Lock early (before optimistic UI / network) — double-tap & overlapping sends.
        isSending = true
        sendGeneration &+= 1
        let gen = sendGeneration

        // Ne JAMAIS injecter les consignes outil dans le message persisté / affiché.
        // Le draftId / thread part via activeContext (system) — sinon l’historique affiche la litanie.
        let displayText = rawText

        var opts = options ?? ChatSendOptions(attachmentIds: ids, mode: chatMode)
        opts.toolChannel = toolChannel.apiValue
        if let editId = editingMessageId {
            opts.editMessageId = editId
        }
        if opts.activeContext == nil {
            opts.activeContext = forcedActiveContext
        }
        // Brouillon ouvert : le chat doit peaufiner CE brouillon (pas une nouvelle conversation).
        if let draftId = draftCardId, !draftId.isEmpty {
            var ctx = opts.activeContext ?? ActiveContextHint()
            ctx.draftId = draftId
            if ctx.mailThreadId == nil {
                ctx.mailThreadId = forcedActiveContext?.mailThreadId
            }
            if ctx.label == nil || ctx.label?.isEmpty == true {
                ctx.label = forcedActiveContext?.label ?? draftCardSubject
            }
            opts.activeContext = ctx
        }

        // Améliorer via composer : le message = consigne pour peaufiner CE brouillon.
        var effectiveRewrite = rewriteDraftCard
        if !effectiveRewrite,
           draftImprovePending,
           draftCardId != nil,
           forcedText == nil,
           options?.regenerate != true {
            effectiveRewrite = true
            draftImprovePending = false
        }

        // API : consigne + corps actuel (sinon le modèle dérive sur l’historique).
        // UI : seule la consigne courte (« moins formel ») apparaît dans le fil.
        let text: String
        if effectiveRewrite, draftCardId != nil {
            text = Self.draftRewriteApiMessage(
                instruction: rawText,
                body: draftCardText,
                to: draftCardTo,
                subject: draftCardSubject
            )
            opts.toolChannel = ComposerToolChannel.email.apiValue
            if opts.mode == "chat" {
                opts.mode = "agent"
            }
        } else {
            text = rawText
        }

        // Brouillon ouvert + PJ : joindre côté produit (indépendant du LLM / des phrases).
        if !effectiveRewrite,
           let draftId = draftCardId,
           !draftId.isEmpty,
           !ids.isEmpty {
            let attached = await syncAttachmentsToOpenDraft(ids)
            if attached {
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
                let names = (localAtts ?? []).compactMap(\.filename).filter { !$0.isEmpty }
                if options?.regenerate != true, !hideUserMessage {
                    messages.append(
                        MessageDTO(
                            id: "local-\(UUID().uuidString)",
                            role: "user",
                            content: displayText.isEmpty ? "📎 Pièce jointe" : displayText,
                            createdAt: nil,
                            attachments: localAtts
                        )
                    )
                }
                pendingAttachments = []
                if forcedScope == .mail {
                    nav.clearMailStickyAttachments()
                }
                let confirm = names.isEmpty
                    ? "Pièce(s) jointe(s) ajoutée(s) au brouillon ouvert."
                    : "Pièce(s) jointe(s) ajoutée(s) au brouillon : \(names.joined(separator: ", "))."
                messages.append(
                    MessageDTO(
                        id: "asst-\(UUID().uuidString)",
                        role: "assistant",
                        content: confirm,
                        createdAt: nil
                    )
                )
                draft = ""
                editingMessageId = nil
                isSending = false
                sendTask = nil
                thinkingKind = nil
                if let pinId = messages.last(where: { $0.role == "user" })?.id {
                    requestPinMessageToTop(pinId)
                } else {
                    scrollToken += 1
                }
                Keyboard.dismiss()
                return
            }
        }

        awaitingDraftRewrite = effectiveRewrite
        draftPreviewReceivedThisTurn = false
        suppressAssistantNarration = effectiveRewrite
        if effectiveRewrite {
            draftCardCollapsed = false
            draftCardStreaming = true
            draftCardStatus = "Amélioration…"
            draftCardEditing = false
        }

        var immediateThinking: ThinkingKind = chatMode == "agent" ? .preparing : .reflecting
        let lower = rawText.lowercased()
        // Statuts Mail uniquement si on est vraiment dans un flux mail (brouillon / contexte mail).
        // Ne pas matcher « à moins » comme « à moi ».
        let inMailFlow = draftCardId != nil
            || forcedActiveContext?.mailThreadId != nil
            || (forcedActiveContext?.label?.localizedCaseInsensitiveContains("mail") == true)
        if draftCardId != nil {
            immediateThinking = .custom(effectiveRewrite ? "Amélioration du brouillon…" : "Mise à jour du brouillon…")
        } else if inMailFlow, Self.containsMailRecipientPhrase(lower) {
            immediateThinking = .custom("Recherche du destinataire…")
        } else if inMailFlow,
                  lower.contains("mail") || lower.contains("email") || lower.contains("brouillon")
                    || lower.contains("écris") || lower.contains("ecris") {
            immediateThinking = .custom("Préparation du brouillon…")
        } else if inMailFlow, lower.contains("résum") || lower.contains("resum") {
            immediateThinking = .custom("Analyse du message…")
        } else if inMailFlow, lower.contains("répond") || lower.contains("repond") {
            immediateThinking = .custom("Préparation de la réponse…")
        } else if chatMode == "agent" {
            immediateThinking = .custom("Planification de l’agent…")
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
                        content: displayText.isEmpty ? "📎 Pièce jointe" : displayText,
                        createdAt: nil,
                        attachments: localAtts
                    )
                )
            } else if !hideUserMessage, let editId = editingMessageId,
                      let idx = messages.firstIndex(where: { $0.id == editId }) {
                messages[idx] = MessageDTO(
                    id: editId,
                    role: "user",
                    content: displayText,
                    createdAt: messages[idx].createdAt,
                    attachments: messages[idx].attachments
                )
                messages = Array(messages.prefix(through: idx))
            }
            pendingAttachments = []
            if forcedScope == .mail {
                nav.clearMailStickyAttachments()
            }
            editingMessageId = nil
        }

        Keyboard.dismiss()
        // Message user en haut du viewport (pas collé en bas).
        if !hideUserMessage, let pinId = messages.last(where: { $0.role == "user" })?.id {
            requestPinMessageToTop(pinId)
        } else {
            scrollToken += 1
        }
        streamingText = ""
        streamAccum.text = ""
        streamScrollTick = 0
        tokenCoalesceBuffer = ""
        tokenFlushTask?.cancel()
        tokenFlushTask = nil
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
        streamingAssistantId = nil
        showScrollDown = false
        runtimeStatus = "BUSY"

        do {
            try await client.sendChat(
                conversationId: conversation.id,
                message: text,
                options: opts,
                streaming: streamingService
            ) { event in
                await MainActor.run {
                    guard gen == sendGeneration else { return }
                    handleSSE(type: event.type, obj: event.payload)
                }
            }
            guard gen == sendGeneration else {
                isSending = false
                sendTask = nil
                return
            }
            if Task.isCancelled {
                // Stop utilisateur : finalizeStoppedStream a déjà géré le partial.
                thinkingKind = nil
                isSending = false
                sendTask = nil
                endChatBackgroundTask()
                await finishDraftRewriteIfNeeded(appliedViaPreview: draftPreviewReceivedThisTurn, fallbackText: streamingText)
                return
            }
            lastSources = streamSources
            lastMailHandoff = streamMailHandoff
            lastFilesHandoff = streamFilesHandoff
            let finalFound = streamFilesFound
            // Garder le texte streamé : MessageBubble masque la narration fichier redondante.
            // Vider ici provoquait un flash (vide ~1s pendant loadMessages, puis réapparition).
            flushTokenCoalesce()
            let finalText = streamAccum.text.isEmpty ? streamingText : streamAccum.text
            let finalSources = streamSources
            let finalMail = streamMailHandoff
            let finalFiles = streamFilesHandoff
            let promoteId = streamingAssistantId ?? "asst-\(UUID().uuidString)"
            let skipPromoteNarration = awaitingDraftRewrite || (suppressAssistantNarration && draftPreviewReceivedThisTurn)
            // Promote in-place AVANT clear/reload — évite le trou « disparaît puis réapparaît ».
            if !skipPromoteNarration,
               !finalText.isEmpty || !finalFound.isEmpty || finalMail != nil || finalFiles != nil || !finalSources.isEmpty {
                if let idx = messages.firstIndex(where: { $0.id == promoteId }) {
                    messages[idx] = MessageDTO(
                        id: promoteId,
                        role: "assistant",
                        content: finalText,
                        createdAt: messages[idx].createdAt,
                        attachments: messages[idx].attachments
                    )
                } else if !finalText.isEmpty || !finalFound.isEmpty {
                    messages.append(
                        MessageDTO(id: promoteId, role: "assistant", content: finalText, createdAt: nil)
                    )
                }
                var meta = chromeById[promoteId] ?? MessageChromeMeta()
                if !finalSources.isEmpty { meta.sources = finalSources }
                if finalMail != nil { meta.mailHandoff = finalMail }
                if finalFiles != nil { meta.filesHandoff = finalFiles }
                if !finalFound.isEmpty { meta.filesFound = finalFound }
                chromeById[promoteId] = meta
                ConversationSessionStore.setChrome(
                    meta,
                    conversationId: conversation.id,
                    messageId: promoteId
                )
            }
            let rewriteFallback = finalText
            let rewriteHadPreview = draftPreviewReceivedThisTurn
            streamingText = ""
            streamAccum.text = ""
            streamFilesFound = []
            streamSources = []
            streamMailHandoff = nil
            streamFilesHandoff = nil
            await finishDraftRewriteIfNeeded(appliedViaPreview: rewriteHadPreview, fallbackText: rewriteFallback)
            guard gen == sendGeneration else {
                isSending = false
                sendTask = nil
                return
            }
            suppressAssistantNarration = false
            // Toujours dédupliquer les cartes fichiers (asst-* + id serveur).
            if !finalFound.isEmpty {
                dedupeAssistantMessagesSharing(
                    fileIds: Set(finalFound.map(\.id)),
                    keepId: promoteId
                )
            }
            if !skipPromoteNarration {
                dedupeTrailingAssistant(matching: finalText, preferId: promoteId)
            }
            // ID serveur déjà stable (assistant_start) : sync soft sans remplacer l’identité ForEach.
            if streamingAssistantId != nil {
                flushTokenCoalesce()
                streamingAssistantId = nil
                if isPinnedToBottom {
                    scrollToken += 1
                }
                Task {
                    contextSnapshot = try? await client.conversationContext(conversationId: conversation.id)
                }
            } else if !skipPromoteNarration {
                await loadMessages(preserveAssistantId: promoteId)
                guard gen == sendGeneration else {
                    isSending = false
                    sendTask = nil
                    return
                }
                if !finalFound.isEmpty {
                    dedupeAssistantMessagesSharing(
                        fileIds: Set(finalFound.map(\.id)),
                        keepId: promoteId
                    )
                }
                dedupeTrailingAssistant(matching: finalText, preferId: promoteId)
                if let last = messages.last(where: { $0.role == "assistant" }) {
                    var meta = chromeById[last.id] ?? MessageChromeMeta()
                    if meta.sources.isEmpty { meta.sources = finalSources }
                    if meta.mailHandoff == nil { meta.mailHandoff = finalMail }
                    if meta.filesHandoff == nil { meta.filesHandoff = finalFiles }
                    if meta.filesFound.isEmpty { meta.filesFound = finalFound }
                    if meta.agentRun == nil {
                        meta.agentRun = chromeById[promoteId]?.agentRun
                    }
                    chromeById[last.id] = meta
                    ConversationSessionStore.setChrome(
                        meta,
                        conversationId: conversation.id,
                        messageId: last.id
                    )
                }
                if isPinnedToBottom {
                    scrollToken += 1
                }
            } else {
                flushTokenCoalesce()
                streamingAssistantId = nil
                if isPinnedToBottom {
                    scrollToken += 1
                }
            }
        } catch is CancellationError {
            thinkingKind = nil
            runtimeStatus = "READY"
            await finishDraftRewriteIfNeeded(appliedViaPreview: draftPreviewReceivedThisTurn, fallbackText: streamingText)
        } catch {
            thinkingKind = nil
            if agentActivity.visible {
                if let start = agentActivity.startedAt {
                    agentActivity.lockedThoughtSeconds = max(1, Int(Date().timeIntervalSince(start)))
                }
                agentActivity.completed = true
                syncAgentChromeToStreamingMessage(completed: true)
                agentActivity = AgentActivityState()
            }
            if Self.isUserCancellation(error) {
                runtimeStatus = "READY"
                await finishDraftRewriteIfNeeded(appliedViaPreview: draftPreviewReceivedThisTurn, fallbackText: streamingText)
            } else if Self.isTransientNetworkDrop(error) {
                // Souvent : app en arrière-plan — le serveur a pu finir quand même.
                runtimeStatus = "READY"
                await loadMessages()
                await finishDraftRewriteIfNeeded(appliedViaPreview: draftPreviewReceivedThisTurn, fallbackText: streamingText)
            } else {
                self.error = friendlyChatSendError(error)
                canRetrySend = true
                AppHaptics.error()
                if case APIClientError.unauthorized = error {
                    await session.logout()
                }
                await refreshRuntimeStatus()
                if runtimeStatus.uppercased() == "BUSY" {
                    runtimeStatus = "READY"
                }
                await finishDraftRewriteIfNeeded(appliedViaPreview: draftPreviewReceivedThisTurn, fallbackText: streamingText)
            }
        }
        if gen == sendGeneration {
            isSending = false
            sendTask = nil
        }
        endChatBackgroundTask()
    }

    private func beginChatBackgroundTaskIfNeeded() {
        guard chatBackgroundTaskId == .invalid else { return }
        chatBackgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "chat-sse") {
            Task { @MainActor in
                // Expiration iOS : libérer le slot, sans cancel du stream serveur.
                if chatBackgroundTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(chatBackgroundTaskId)
                    chatBackgroundTaskId = .invalid
                }
            }
        }
    }

    private func endChatBackgroundTask() {
        guard chatBackgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(chatBackgroundTaskId)
        chatBackgroundTaskId = .invalid
    }

    private func friendlyChatSendError(_ error: Error) -> String {
        if case APIClientError.http(let code, let body) = error {
            let lower = body.lowercased()
            if code == 502 || code == 503 {
                if lower.contains("backend_offline") || lower.contains("injoignable") || lower.contains("indisponible") {
                    return "Le PC est momentanément injoignable. Réessaie dans quelques secondes."
                }
                return "Connexion interrompue. Réessaie — le serveur a eu un trou d’air."
            }
            if code >= 500 {
                return "Le serveur a rencontré une erreur (HTTP \(code)). Réessaie."
            }
            if !body.isEmpty && body != "SSE failed" {
                return body
            }
            return "HTTP \(code)"
        }
        return error.localizedDescription
    }

    /// Stop utilisateur / invalidate URLSession — pas une erreur à afficher.
    private static func isUserCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return true }
        let msg = error.localizedDescription.lowercased()
        return msg == "cancelled" || msg == "canceled" || msg.contains("annul")
    }

    /// Coupure réseau typique quand iOS suspend l’app — resync plutôt qu’alerter.
    private static func isTransientNetworkDrop(_ error: Error) -> Bool {
        if let url = error as? URLError {
            switch url.code {
            case .networkConnectionLost, .timedOut, .notConnectedToInternet,
                 .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff:
                return true
            default:
                break
            }
        }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                 NSURLErrorNotConnectedToInternet, NSURLErrorCannotConnectToHost:
                return true
            default:
                break
            }
        }
        return false
    }

    /// « à moi » / « a moi » en frontières de mots — évite « à moins ».
    private static func containsMailRecipientPhrase(_ haystack: String) -> Bool {
        let phrases = ["moi-même", "moi meme", "à moi", "a moi", "destinataire"]
        for phrase in phrases {
            let pattern = "(?<![\\p{L}\\p{N}])\(NSRegularExpression.escapedPattern(for: phrase))(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(haystack.startIndex..., in: haystack)
            if regex.firstMatch(in: haystack, options: [], range: range) != nil {
                return true
            }
        }
        return false
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
        shouldShowLiveAgentStrip
    }

    /// Panel agent live : uniquement si un vrai run Agent a démarré.
    /// Chat + web search seul → ThinkingStatusView (pas « Préparation du plan… »).
    private var shouldShowLiveAgentStrip: Bool {
        guard !agentActivity.completed else { return false }
        return agentActivity.visible
    }

    /// Query outil depuis le payload SSE (`query` top-level ou `input.query`).
    private func toolQuery(from obj: [String: Any]) -> String? {
        if let q = obj["query"] as? String {
            let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        if let input = obj["input"] as? [String: Any],
           let q = input["query"] as? String {
            let t = q.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// Libellé court d’une source web (domaine préféré).
    private func shortWebSourceLabel(domain: String?, title: String?, url: String?) -> String {
        if let domain, !domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return domain.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
        }
        if let url, let host = URL(string: url)?.host, !host.isEmpty {
            return host.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
        }
        if let title {
            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return String(t.prefix(42)) }
        }
        return "source"
    }

    private func liveSourceStatusLine(
        phase: String,
        domain: String?,
        title: String?,
        url: String?,
        index: Int?,
        total: Int?
    ) -> String {
        let label = shortWebSourceLabel(domain: domain, title: title, url: url)
        let verb: String
        switch phase {
        case "fetching": verb = "Lecture"
        case "done": verb = "Sources"
        default: verb = "Analyse"
        }
        if let index, let total, total > 1 {
            return "\(verb) · \(label) (\(index)/\(total))"
        }
        return "\(verb) · \(label)"
    }

    /// Attache / met à jour le panel agent sur le message assistant courant (persistance conversation).
    /// Ancre message dédiée à ce run agent — ne jamais réutiliser un ancien assistant.
    @discardableResult
    private func ensureAgentRunAnchorMessage(forceNew: Bool = false) -> String {
        if let current = streamingAssistantId,
           messages.contains(where: { $0.id == current }) {
            let alreadyFinalized = chromeById[current]?.agentRun?.completed == true
            // forceNew n'abandonne l'ancre que si elle porte déjà un panel terminé (autre tour).
            if !forceNew || !alreadyFinalized {
                return current
            }
        }
        let id = "asst-agent-\(UUID().uuidString)"
        streamingAssistantId = id
        if !messages.contains(where: { $0.id == id }) {
            messages.append(
                MessageDTO(id: id, role: "assistant", content: "", createdAt: nil)
            )
        }
        return id
    }

    private func syncAgentChromeToStreamingMessage(completed: Bool = false) {
        guard agentActivity.visible || !agentActivity.planSteps.isEmpty || agentActivity.webPhase != .idle else { return }
        var snap = agentActivity.snapshot()
        if !completed {
            snap.completed = agentActivity.completed
            // Pendant le run : ne pas forcer toutes les étapes à done.
            snap.planSteps = agentActivity.planSteps
            // Ne pas figer thoughtSeconds ici — le strip live tick depuis startedAt.
            snap.thoughtSeconds = nil
        }
        // Jamais de fallback sur le dernier assistant : ça écrasait le panel du tour précédent.
        let id = ensureAgentRunAnchorMessage()
        var chrome = chromeById[id] ?? MessageChromeMeta()
        chrome.agentRun = snap
        chromeById[id] = chrome
        ConversationSessionStore.setChrome(
            chrome,
            conversationId: conversation.id,
            messageId: id
        )
    }

    /// Active l’étape `index` sans inventer de « done » sur les précédentes.
    /// La clôture des étapes vient du backend (`agent_step_update` / plan final).
    private func activateAgentPlanStep(at index: Int) {
        guard !agentActivity.planSteps.isEmpty else { return }
        let idx = min(max(0, index), agentActivity.planSteps.count - 1)
        for i in agentActivity.planSteps.indices {
            if i == idx {
                let st = agentActivity.planSteps[i].status
                if st != "done" && st != "error" && st != "skipped" {
                    agentActivity.planSteps[i].status = "running"
                }
                agentActivity.currentStepTitle = agentActivity.planSteps[i].title
                agentActivity.stepIndex = i
            }
        }
        agentActivity.totalSteps = max(agentActivity.totalSteps, agentActivity.planSteps.count)
    }

    private func activateAgentPlanStep(id: String?) {
        guard let id,
              let i = agentActivity.planSteps.firstIndex(where: { $0.id == id }) else { return }
        activateAgentPlanStep(at: i)
    }

    private func inferAgentPlanStepIndex(from title: String?) -> Int? {
        guard let title, !title.isEmpty, !agentActivity.planSteps.isEmpty else { return nil }
        let lower = title.lowercased()
        if let i = agentActivity.planSteps.firstIndex(where: { $0.title.lowercased() == lower }) {
            return i
        }
        if let i = agentActivity.planSteps.firstIndex(where: {
            let t = $0.title.lowercased()
            return t.contains(lower.prefix(16)) || lower.contains(t.prefix(16))
        }) {
            return i
        }
        if lower.contains("synth") || lower.contains("rédig") || lower.contains("repond")
            || lower.contains("répond") || lower.contains("présentation") {
            return agentActivity.planSteps.count - 1
        }
        if lower.contains("analys") || lower.contains("compar") || lower.contains("évalu")
            || lower.contains("evidence") {
            return min(1, agentActivity.planSteps.count - 1)
        }
        if lower.contains("recherch") || lower.contains("search") || lower.contains("web")
            || lower.contains("benchmark") {
            return 0
        }
        return nil
    }

    private func applyAgentPlanFromPayload(_ plan: [String: Any]) {
        guard let steps = plan["steps"] as? [[String: Any]] else { return }
        agentActivity.planSteps = steps.enumerated().map { idx, s in
            let rawStatus = (s["status"] as? String) ?? "pending"
            return AgentPlanStep(
                id: (s["id"] as? String) ?? "\(idx)",
                title: AgentToolLabels.friendlyStepTitle(
                    (s["title"] as? String) ?? (s["goal"] as? String) ?? "Étape \(idx + 1)"
                ),
                status: AgentToolLabels.normalizeStepStatus(rawStatus)
            )
        }
        agentActivity.totalSteps = agentActivity.planSteps.count
        if let running = agentActivity.planSteps.first(where: { $0.status == "running" }) {
            agentActivity.currentStepTitle = running.title
            agentActivity.phase = "executing"
            agentActivity.stepIndex = agentActivity.planSteps.firstIndex(where: { $0.id == running.id }) ?? 0
        } else if let first = agentActivity.planSteps.first {
            agentActivity.currentStepTitle = first.title
        }
    }

    private func progressAgentPlanForWebPhase(_ phase: WebSearchPhase) {
        guard !agentActivity.planSteps.isEmpty else { return }
        switch phase {
        case .searching:
            activateAgentPlanStep(at: 0)
        case .analyzing, .done:
            activateAgentPlanStep(at: min(1, agentActivity.planSteps.count - 1))
        case .idle:
            break
        }
    }

    private func finalizeStoppedStream() {
        isSending = false
        thinkingKind = nil
        if agentActivity.visible || agentActivity.webPhase != .idle || !agentActivity.planSteps.isEmpty {
            if let start = agentActivity.startedAt {
                agentActivity.lockedThoughtSeconds = max(1, Int(Date().timeIntervalSince(start)))
            }
            agentActivity.completed = true
            agentActivity.visible = true
            syncAgentChromeToStreamingMessage(completed: true)
            agentActivity = AgentActivityState()
        } else {
            agentActivity = AgentActivityState()
        }
        if !streamAccum.text.isEmpty || !streamingText.isEmpty {
            let partial = streamAccum.text.isEmpty ? streamingText : streamAccum.text
            messages.append(
                MessageDTO(
                    id: "partial-\(UUID().uuidString)",
                    role: "assistant",
                    content: partial,
                    createdAt: nil
                )
            )
            streamingText = ""
            streamAccum.text = ""
            if isPinnedToBottom {
                scrollToken += 1
            }
        }
        Task { @MainActor in
            runtimeStatus = (try? await client.runtimeStatus()) ?? runtimeStatus
        }
        AppHaptics.light()
    }

    private func scheduleStreamScroll(proxy: ScrollViewProxy) {
        let now = Date()
        guard now.timeIntervalSince(lastStreamScrollAt) >= 0.05 else { return }
        lastStreamScrollAt = now
        suppressScrollGeometryUntil = Date().addingTimeInterval(0.25)
        var t = Transaction()
        t.animation = nil
        withTransaction(t) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func flushTokenCoalesce() {
        tokenFlushTask?.cancel()
        tokenFlushTask = nil
        let chunk = tokenCoalesceBuffer
        tokenCoalesceBuffer = ""
        streamingText = streamAccum.text
        guard !chunk.isEmpty, let id = streamingAssistantId,
              let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        let prev = messages[idx]
        messages[idx] = MessageDTO(
            id: id,
            role: "assistant",
            content: prev.content + chunk,
            createdAt: prev.createdAt,
            attachments: prev.attachments
        )
        streamScrollTick &+= 1
    }

    private func handleSSE(type: String, obj: [String: Any]) {
        switch type {
        case "token":
            if let c = obj["content"] as? String {
                streamAccum.text += c
                // Dès que la réponse s’écrit : basculer l’étape courante vers la synthèse.
                if agentActivity.visible,
                   !agentActivity.planSteps.isEmpty,
                   agentActivity.phase != "synthesis",
                   agentActivity.phase != "synthesizing" {
                    agentActivity.phase = "synthesis"
                    activateAgentPlanStep(at: max(0, agentActivity.planSteps.count - 1))
                }
                // Réécriture brouillon : accumuler pour fallback, ne pas afficher dans le fil.
                if awaitingDraftRewrite || suppressAssistantNarration {
                    streamingText = streamAccum.text
                    thinkingKind = nil
                    break
                }
                // Coalesce ~33ms (~30 fps) : UI fluide sans re-render à chaque token.
                tokenCoalesceBuffer += c
                if tokenFlushTask == nil {
                    tokenFlushTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 33_000_000)
                        let chunk = tokenCoalesceBuffer
                        tokenCoalesceBuffer = ""
                        tokenFlushTask = nil
                        streamingText = streamAccum.text
                        if !chunk.isEmpty, let id = streamingAssistantId,
                           let idx = messages.firstIndex(where: { $0.id == id }) {
                            let prev = messages[idx]
                            messages[idx] = MessageDTO(
                                id: id,
                                role: "assistant",
                                content: prev.content + chunk,
                                createdAt: prev.createdAt,
                                attachments: prev.attachments
                            )
                        }
                        streamScrollTick &+= 1
                    }
                }
            }
            thinkingKind = nil
        case "status", "thinking", "runtime_status":
            if type == "runtime_status", let st = obj["status"] as? String {
                runtimeStatus = st
                // Ne jamais afficher READY/BUSY comme texte « réflexion » dans le fil.
                if !awaitingDraftRewrite, !agentActivity.visible, st == "analyzing_web" {
                    let shouldReplace: Bool = {
                        guard let thinkingKind else { return true }
                        if thinkingKind == .searching { return true }
                        if case .custom(let s) = thinkingKind {
                            return s.hasPrefix("Recherche ·") || s.hasPrefix("Lecture ·")
                        }
                        return false
                    }()
                    if shouldReplace {
                        thinkingKind = .custom("Analyse des pages…")
                    }
                }
                break
            }
            if !agentActivity.visible {
                let msg = (obj["message"] as? String) ?? (obj["status"] as? String)
                if let kind = ThinkingKind.fromSSE(type: type, message: msg) {
                    thinkingKind = kind
                }
            }
        case "tool_start":
            let tool = (obj["tool"] as? String) ?? (obj["name"] as? String) ?? ""
            if agentActivity.visible {
                agentActivity.currentStepTitle = AgentToolLabels.humanize(tool.isEmpty ? "outil" : tool)
                agentActivity.phase = "executing"
                if tool.lowercased().contains("search") {
                    agentActivity.webPhase = .searching
                    agentActivity.webQuery = toolQuery(from: obj) ?? agentActivity.webQuery
                }
            } else if tool.lowercased().contains("search") {
                // Chat + web : indicateur léger, pas de panel agent/plan.
                thinkingKind = .searching
            } else if let kind = ThinkingKind.fromSSE(type: type, message: tool) {
                thinkingKind = kind
            }
        case "tool_done", "tool_result":
            if awaitingDraftRewrite {
                // Pas d’indicateur « Recherche · N sources » pendant une réécriture mail.
                break
            }
            if agentActivity.visible {
                if agentActivity.webPhase == .searching || agentActivity.webPhase == .analyzing {
                    agentActivity.webPhase = .analyzing
                }
                if let summary = obj["summary"] as? String, !summary.isEmpty {
                    agentActivity.currentStepTitle = AgentToolLabels.humanize(summary)
                }
            } else if !agentActivity.visible {
                let count = (obj["sourceCount"] as? Int) ?? (obj["source_count"] as? Int)
                if let count, count > 0 {
                    thinkingKind = .custom(
                        "Recherche · \(count) source\(count > 1 ? "s" : "")"
                    )
                } else {
                    thinkingKind = .preparing
                }
            }
        case "tool_error":
            let raw = (obj["message"] as? String) ?? (obj["error"] as? String)
            if agentActivity.visible {
                agentActivity.lastError = AgentToolLabels.friendlyError(raw)
            } else {
                thinkingKind = .custom(AgentToolLabels.friendlyError(raw))
            }
        case "web_search":
            // Réécriture brouillon mail : ignorer toute UI / état recherche web.
            if awaitingDraftRewrite { break }
            let q = toolQuery(from: obj) ?? (obj["message"] as? String) ?? "Recherche web…"
            if agentActivity.visible {
                agentActivity.webQuery = q
                agentActivity.webPhase = .searching
                progressAgentPlanForWebPhase(.searching)
            } else {
                thinkingKind = .searching
            }
        case "agent_start":
            let startedFresh = !agentActivity.visible
            thinkingKind = nil
            agentActivity.visible = true
            agentActivity.completed = false
            agentActivity.lastError = nil
            agentActivity.phase = "planning"
            agentActivity.startedAt = Date()
            agentActivity.lockedThoughtSeconds = nil
            agentActivity.activitySummary = nil
            agentActivity.planSteps = []
            // Force une nouvelle ancre : ne pas réécrire le panel d’un message déjà finalisé.
            _ = ensureAgentRunAnchorMessage(forceNew: true)
            if startedFresh { AppHaptics.light() }
        case "agent_plan":
            thinkingKind = nil
            agentActivity.visible = true
            agentActivity.completed = false
            agentActivity.phase = "planning"
            if agentActivity.startedAt == nil { agentActivity.startedAt = Date() }
            if let plan = obj["plan"] as? [String: Any],
               let steps = plan["steps"] as? [[String: Any]] {
                agentActivity.planSteps = steps.enumerated().map { idx, s in
                    let rawStatus = (s["status"] as? String) ?? "pending"
                    return AgentPlanStep(
                        id: (s["id"] as? String) ?? "\(idx)",
                        title: AgentToolLabels.friendlyStepTitle(
                            (s["title"] as? String) ?? (s["goal"] as? String) ?? "Étape \(idx + 1)"
                        ),
                        status: AgentToolLabels.normalizeStepStatus(rawStatus)
                    )
                }
                agentActivity.totalSteps = agentActivity.planSteps.count
                if let running = agentActivity.planSteps.first(where: { $0.status == "running" }) {
                    agentActivity.currentStepTitle = running.title
                    agentActivity.phase = "executing"
                    agentActivity.stepIndex = agentActivity.planSteps.firstIndex(where: { $0.id == running.id }) ?? 0
                } else if let first = agentActivity.planSteps.first {
                    agentActivity.currentStepTitle = first.title
                }
            }
            syncAgentChromeToStreamingMessage()
        case "agent_step", "agent_step_update":
            thinkingKind = nil
            agentActivity.visible = true
            agentActivity.phase = "executing"
            if let idx = obj["stepIndex"] as? Int { agentActivity.stepIndex = idx }
            if let total = obj["totalSteps"] as? Int { agentActivity.totalSteps = total }
            if let stepId = obj["stepId"] as? String,
               let i = agentActivity.planSteps.firstIndex(where: { $0.id == stepId }) {
                let st = AgentToolLabels.normalizeStepStatus((obj["status"] as? String) ?? "running")
                agentActivity.planSteps[i].status = st
                if let title = obj["title"] as? String, !title.isEmpty {
                    agentActivity.planSteps[i].title = AgentToolLabels.friendlyStepTitle(title)
                }
                agentActivity.currentStepTitle = agentActivity.planSteps[i].title
                // Ne pas forcer done sur les précédentes : le backend envoie skipped/done.
                if st == "error" {
                    agentActivity.lastError = AgentToolLabels.friendlyError(obj["message"] as? String)
                }
            } else if let msg = obj["message"] as? String {
                agentActivity.currentStepTitle = AgentToolLabels.friendlyStepTitle(msg)
            }
            syncAgentChromeToStreamingMessage()
        case "agent_action_start":
            agentActivity.visible = true
            agentActivity.phase = "executing"
            if let stepId = obj["stepId"] as? String {
                activateAgentPlanStep(id: stepId)
            }
            if let action = obj["action"] as? [String: Any] {
                let tool = (action["tool"] as? String) ?? ""
                let raw =
                    (action["summary"] as? String)
                    ?? (tool.isEmpty ? nil : tool)
                    ?? (action["type"] as? String)
                agentActivity.currentStepTitle = raw.map(AgentToolLabels.humanize)
                if tool.lowercased().contains("search") || tool.lowercased().contains("web") {
                    agentActivity.webPhase = .searching
                    if let q = toolQuery(from: action) ?? toolQuery(from: obj) {
                        agentActivity.webQuery = q
                    }
                }
                if let label = raw.map(AgentToolLabels.humanize) {
                    var parts = (agentActivity.activitySummary ?? "")
                        .split(separator: "·")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                    if !parts.contains(label) {
                        parts.append(label)
                        agentActivity.activitySummary = parts.filter { !$0.isEmpty }.joined(separator: " · ")
                    }
                }
            } else if let title = agentActivity.currentStepTitle,
                      let idx = inferAgentPlanStepIndex(from: title) {
                activateAgentPlanStep(at: idx)
            }
            syncAgentChromeToStreamingMessage()
        case "agent_action_done":
            agentActivity.visible = true
            if let summary = obj["summary"] as? String, !summary.isEmpty {
                agentActivity.currentStepTitle = AgentToolLabels.humanize(summary)
            }
            if let count = obj["sourceCount"] as? Int, count > 0 {
                let bit = "\(count) source\(count > 1 ? "s" : "")"
                if let base = agentActivity.activitySummary, !base.isEmpty, !base.contains("source") {
                    agentActivity.activitySummary = "\(base) · \(bit)"
                } else if agentActivity.activitySummary == nil {
                    agentActivity.activitySummary = bit
                }
                if agentActivity.webPhase == .searching {
                    agentActivity.webPhase = .analyzing
                    progressAgentPlanForWebPhase(.analyzing)
                }
            }
            syncAgentChromeToStreamingMessage()
        case "agent_status":
            agentActivity.visible = true
            if let phase = obj["phase"] as? String {
                agentActivity.phase = phase
                if phase == "synthesizing" || phase == "synthesis" {
                    activateAgentPlanStep(at: max(0, agentActivity.planSteps.count - 1))
                }
            }
            if let total = obj["totalSteps"] as? Int { agentActivity.totalSteps = total }
            if let idx = obj["stepIndex"] as? Int {
                activateAgentPlanStep(at: idx)
            } else if let title = (obj["currentStepTitle"] as? String) ?? (obj["message"] as? String),
                      !title.isEmpty {
                agentActivity.currentStepTitle = AgentToolLabels.friendlyStepTitle(title)
                if let inferred = inferAgentPlanStepIndex(from: title) {
                    activateAgentPlanStep(at: inferred)
                }
            }
            syncAgentChromeToStreamingMessage()
        case "agent_done":
            agentActivity.visible = true
            agentActivity.phase = "synthesis"
            if let plan = obj["plan"] as? [String: Any] {
                applyAgentPlanFromPayload(plan)
            } else {
                for i in agentActivity.planSteps.indices
                where agentActivity.planSteps[i].status == "running" || agentActivity.planSteps[i].status == "pending" {
                    agentActivity.planSteps[i].status = "done"
                }
            }
            if let msg = obj["message"] as? String, !msg.isEmpty {
                agentActivity.currentStepTitle = msg
            }
            syncAgentChromeToStreamingMessage()
        case "assistant_start":
            if let id = obj["messageId"] as? String, !id.isEmpty {
                // Si files_found a déjà créé un asst-* local : fusionner vers l’ID serveur
                // (sinon → 2 bulles CI).
                remountStreamingAssistant(onto: id)
                syncAgentChromeToStreamingMessage()
            }
            if !agentActivity.visible && streamFilesFound.isEmpty {
                thinkingKind = .preparing
            }
        case "assistant_discard":
            if let id = obj["messageId"] as? String, streamingAssistantId == id {
                streamingText = ""
                streamAccum.text = ""
                flushTokenCoalesce()
                streamingAssistantId = nil
                if let idx = messages.firstIndex(where: { $0.id == id }) {
                    messages.remove(at: idx)
                }
                chromeById.removeValue(forKey: id)
                if !agentActivity.visible {
                    thinkingKind = .preparing
                }
            }
        case "sources":
            // Réécriture brouillon : pas de pastilles « N sources » (canal mail, pas web).
            if awaitingDraftRewrite { break }
            if agentActivity.visible {
                agentActivity.webPhase = .analyzing
                progressAgentPlanForWebPhase(.analyzing)
            }
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
            if !streamSources.isEmpty {
                let count = streamSources.count
                let bit = "\(count) source\(count > 1 ? "s" : "")"
                let first = streamSources.first
                let firstLabel = shortWebSourceLabel(
                    domain: first?.domain,
                    title: first?.title,
                    url: first?.url
                )
                if agentActivity.visible {
                    if let q = agentActivity.webQuery, !q.isEmpty {
                        agentActivity.activitySummary = "Recherche · \(q) · \(bit)"
                    } else if let base = agentActivity.activitySummary, !base.isEmpty, !base.contains("source") {
                        agentActivity.activitySummary = "\(base) · \(bit)"
                    } else {
                        agentActivity.activitySummary = bit
                    }
                    agentActivity.currentStepTitle = "Lecture · \(firstLabel)"
                    syncAgentChromeToStreamingMessage()
                } else {
                    // Teaser immédiat ; `source_progress` affine domaine par domaine.
                    thinkingKind = .custom("Lecture · \(firstLabel) · \(bit)")
                }
            }
        case "source_progress":
            if awaitingDraftRewrite { break }
            let phase = (obj["phase"] as? String) ?? "analyzing"
            if phase == "done" { break }
            let line = liveSourceStatusLine(
                phase: phase,
                domain: obj["domain"] as? String,
                title: obj["title"] as? String,
                url: obj["url"] as? String,
                index: obj["index"] as? Int,
                total: obj["total"] as? Int
            )
            if agentActivity.visible {
                agentActivity.webPhase = .analyzing
                progressAgentPlanForWebPhase(.analyzing)
                agentActivity.currentStepTitle = line
                syncAgentChromeToStreamingMessage()
            } else {
                thinkingKind = .custom(line)
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
            let parsed: [SavedMemoryChipDTO] = ((obj["memories"] as? [[String: Any]]) ?? []).compactMap { item in
                guard let id = item["id"] as? String, !id.isEmpty else { return nil }
                let content = (item["content"] as? String) ?? (item["text"] as? String) ?? ""
                guard !content.isEmpty else { return nil }
                return SavedMemoryChipDTO(
                    id: id,
                    content: content,
                    category: (item["category"] as? String) ?? "other"
                )
            }
            guard !parsed.isEmpty else { break }
            let targetId = (obj["messageId"] as? String)
                ?? streamingAssistantId
                ?? messages.last(where: { $0.role == "assistant" })?.id
            if let targetId {
                var chrome = chromeById[targetId] ?? MessageChromeMeta()
                var byId = Dictionary(uniqueKeysWithValues: chrome.savedMemories.map { ($0.id, $0) })
                for item in parsed { byId[item.id] = item }
                chrome.savedMemories = Array(byId.values)
                chromeById[targetId] = chrome
                ConversationSessionStore.mergeChrome(
                    MessageChromeMeta(savedMemories: chrome.savedMemories),
                    conversationId: conversation.id,
                    messageId: targetId
                )
            }
            // Pas de toast : l'indicateur « Souvenir mis à jour » est à côté d'Assistant.
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
                var seen = Set<String>()
                let parsed: [FilesFoundFileDTO] = arr.compactMap { f in
                    guard let id = f["fileId"] as? String, !id.isEmpty else { return nil }
                    guard seen.insert(id).inserted else { return nil }
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
                guard !parsed.isEmpty else { return }
                streamFilesFound = parsed
                suppressAssistantNarration = true
                thinkingKind = nil

                // Une seule bulle pour ces fichiers — réutilise l’ancre existante.
                let anchorId = ensureSingleFilesFoundAnchor(for: parsed)
                streamingAssistantId = anchorId
                var chrome = chromeById[anchorId] ?? MessageChromeMeta()
                chrome.filesFound = mergeFilesFound(chrome.filesFound, parsed)
                chromeById[anchorId] = chrome
                ConversationSessionStore.mergeChrome(
                    chrome,
                    conversationId: conversation.id,
                    messageId: anchorId
                )
                // Purge toute autre bulle qui afficherait la même CI.
                dedupeAssistantMessagesSharing(fileIds: Set(parsed.map(\.id)), keepId: anchorId)
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
                    draftCardAttachments = APIClient.parseDraftAttachments(draft["attachments"])
                    draftCardStatus = "Brouillon"
                    draftCardSent = false
                    draftCardCollapsed = false
                    draftInConversation = true
                    draftCardStreaming = false
                    draftPreviewReceivedThisTurn = true
                    suppressAssistantNarration = true
                    streamingText = ""
                    streamAccum.text = ""
                    draftCardEditing = false
                    thinkingKind = nil
                    persistDraftCardSnapshot()
                    // Si le preview SSE n’embarque pas encore les PJ, resync GET.
                    if draftCardAttachments.isEmpty {
                        Task { await refreshDraftCardAttachments(draftId: id) }
                    }
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
                AppHaptics.light()
                return
            }
            let msg = obj["message"] as? String ?? "Erreur"
            if agentActivity.visible {
                agentActivity.lastError = AgentToolLabels.friendlyError(msg)
            }
            error = AgentToolLabels.friendlyError(msg)
            AppHaptics.error()
        case "done":
            thinkingKind = nil
            if agentActivity.visible || agentActivity.webPhase != .idle || !agentActivity.planSteps.isEmpty {
                if let start = agentActivity.startedAt {
                    agentActivity.lockedThoughtSeconds = max(1, Int(Date().timeIntervalSince(start)))
                }
                agentActivity.completed = true
                agentActivity.phase = "synthesis"
                agentActivity.visible = true
                for i in agentActivity.planSteps.indices
                where agentActivity.planSteps[i].status == "running" {
                    agentActivity.planSteps[i].status = "done"
                }
                syncAgentChromeToStreamingMessage(completed: true)
                // Le panel reste dans le fil via chrome — on retire seulement l’état live.
                agentActivity = AgentActivityState()
            } else {
                agentActivity = AgentActivityState()
            }
            Task { @MainActor in
                runtimeStatus = (try? await client.runtimeStatus()) ?? runtimeStatus
            }
            var chrome = MessageChromeMeta(
                sources: streamSources,
                mailHandoff: streamMailHandoff,
                filesHandoff: streamFilesHandoff,
                filesFound: streamFilesFound
            )
            if let id = streamingAssistantId ?? (obj["messageId"] as? String) {
                // Préserve le panel agent déjà syncé + souvenirs SSE.
                if chromeById[id]?.agentRun != nil {
                    chrome.agentRun = chromeById[id]?.agentRun
                }
                if let existing = chromeById[id]?.savedMemories, !existing.isEmpty {
                    chrome.savedMemories = existing
                }
                chromeById[id] = {
                    var merged = chromeById[id] ?? MessageChromeMeta()
                    if !chrome.sources.isEmpty { merged.sources = chrome.sources }
                    if chrome.mailHandoff != nil { merged.mailHandoff = chrome.mailHandoff }
                    if chrome.filesHandoff != nil { merged.filesHandoff = chrome.filesHandoff }
                    if !chrome.filesFound.isEmpty { merged.filesFound = chrome.filesFound }
                    if merged.savedMemories.isEmpty, !chrome.savedMemories.isEmpty {
                        merged.savedMemories = chrome.savedMemories
                    }
                    return merged
                }()
                if let final = chromeById[id] {
                    ConversationSessionStore.setChrome(
                        final,
                        conversationId: conversation.id,
                        messageId: id
                    )
                }
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

    private let cardWidth: CGFloat = 120
    private let previewHeight: CGFloat = 64
    private var previewWidth: CGFloat { cardWidth - 16 } // padding horizontal 8+8

    private var sizeLabel: String {
        let kind = attachment.isImage ? "Image" : "Document"
        return "\(kind) · \(ByteCountFormatter.string(fromByteCount: Int64(attachment.sizeBytes), countStyle: .file))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                attachmentPreview
                    .frame(width: previewWidth, height: previewHeight)

                // Croix inset dans la preview (jamais en offset hors tile).
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.72))
                        .font(.system(size: 18, weight: .semibold))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .padding(5)
                .accessibilityLabel("Retirer \(attachment.filename)")
            }
            .frame(width: previewWidth, height: previewHeight)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))

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
        .frame(width: cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .fill(AppTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
    }

    /// Preview image/doc — même pattern que Files grille : overlay dans un
    /// frame fixe + compositingGroup + clip. Empêche scaledToFill de sortir
    /// de la tile (bug Files → Mail).
    @ViewBuilder
    private var attachmentPreview: some View {
        Color.clear
            .overlay {
                Group {
                    if let data = attachment.previewData, let ui = UIImage(data: data) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    } else {
                        ZStack {
                            AppTheme.surfaceHover.opacity(0.7)
                            Image(systemName: attachment.isImage ? "photo" : "doc.fill")
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                }
            }
            .overlay {
                if attachment.isUploading {
                    ZStack {
                        Color.black.opacity(0.45)
                        ProgressView().tint(.white)
                    }
                }
            }
            .compositingGroup()
            .clipped()
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
