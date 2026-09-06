import SwiftUI
import PhotosUI

/// Composer Mobile 3.0 — attach fiable, options en sheet (reste ouverte), surface opaque stable.
struct ComposerCapsule: View {
    @Binding var draft: String
    @Binding var photoItem: PhotosPickerItem?
    @Binding var showTools: Bool
    let placeholder: String
    let canSend: Bool
    let isSending: Bool
    let uploading: Bool
    let editing: Bool

    var chatMode: String = "chat"
    var webSearchEnabled: Bool = false
    var selectedModelName: String = ""
    var reasoningModes: [ReasoningModeDTO] = []
    var reasoningEffort: String = ""
    var models: [ModelOptionDTO] = []
    var modelSwitching: Bool = false
    var thinkingEnabled: Bool = false
    var thinkingAvailable: Bool = false
    var toolChannel: ComposerToolChannel = .web
    /// `false` dans les assistants Mail / Files (canal imposé).
    var showsToolChannelPicker: Bool = true

    var onModeChange: ((String) -> Void)?
    var onWebChange: ((Bool) -> Void)?
    var onModelChange: ((String) -> Void)?
    var onReasoningChange: ((String) -> Void)?
    var onToggleThinking: (() -> Void)?
    var onSelectToolChannel: ((ComposerToolChannel) -> Void)?

    let onSend: () -> Void
    let onStop: () -> Void
    let onPickDoc: () -> Void
    var onCancelEdit: (() -> Void)? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space8) {
            // Pas de bouton « Fermer » dans/près du composer — dismiss clavier via tap/scroll.

            if editing {
                HStack(spacing: AppTheme.space8) {
                    Label("Édition", systemImage: "pencil")
                        .font(CNFont.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    Spacer(minLength: 0)
                    if let onCancelEdit {
                        Button("Annuler", action: onCancelEdit)
                            .font(CNFont.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .padding(.horizontal, AppTheme.space4)
            }

            HStack(alignment: .bottom, spacing: AppTheme.space4) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.secondary)
                        .frame(width: AppTheme.touchMin, height: AppTheme.touchMin)
                        .contentShape(Rectangle())
                }
                .disabled(uploading || isSending)
                .accessibilityLabel("Joindre une image")
                .accessibilityIdentifier(A11yID.Chat.attachImage)

                Button(action: onPickDoc) {
                    Group {
                        if uploading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(AppTheme.secondary)
                        } else {
                            Image(systemName: "paperclip")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppTheme.secondary)
                        }
                    }
                    .frame(width: AppTheme.touchMin, height: AppTheme.touchMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(uploading || isSending)
                .accessibilityLabel("Joindre un fichier")
                .accessibilityIdentifier(A11yID.Chat.attachFile)

                Button {
                    showTools = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)
                        .frame(width: AppTheme.touchMin, height: AppTheme.touchMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSending)
                .accessibilityLabel("Options du chat")
                .accessibilityIdentifier(A11yID.Chat.overflow)

                TextField(placeholder, text: $draft, axis: .vertical)
                    .lineLimit(1...8)
                    .font(CNFont.body)
                    .foregroundStyle(AppTheme.foreground)
                    .focused($fieldFocused)
                    .padding(.vertical, AppTheme.space12)
                    .accessibilityLabel(placeholder)
                    .accessibilityIdentifier(A11yID.Chat.composerField)

                sendOrStop
            }
            .padding(.horizontal, AppTheme.space8)
            .padding(.vertical, AppTheme.space4)
            .modifier(ComposerGlassChrome(editing: editing, reduceTransparency: reduceTransparency))
        }
        .accessibilityIdentifier(A11yID.Chat.composer)
        .animation(.spring(response: AppTheme.motionQuick, dampingFraction: 0.82), value: isSending)
        .sheet(isPresented: $showTools) {
            ChatToolsSheet(
                chatMode: chatMode,
                webSearchEnabled: webSearchEnabled,
                selectedModelName: selectedModelName,
                models: models,
                reasoningModes: reasoningModes,
                reasoningEffort: reasoningEffort,
                modelSwitching: modelSwitching,
                thinkingEnabled: thinkingEnabled,
                thinkingAvailable: thinkingAvailable,
                toolChannel: toolChannel,
                showsToolChannelPicker: showsToolChannelPicker,
                onModeChange: { onModeChange?($0) },
                onWebChange: { onWebChange?($0) },
                onModelChange: { onModelChange?($0) },
                onReasoningChange: { onReasoningChange?($0) },
                onToggleThinking: { onToggleThinking?() },
                onSelectToolChannel: { onSelectToolChannel?($0) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var sendOrStop: some View {
        Group {
            if isSending {
                Button {
                    AppHaptics.light()
                    onStop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: AppTheme.touchMin, height: AppTheme.touchMin)
                        .background(AppTheme.danger, in: Circle())
                }
                .accessibilityLabel("Arrêter la génération")
                .accessibilityIdentifier(A11yID.Chat.stop)
            } else {
                Button {
                    fieldFocused = false
                    Keyboard.dismiss()
                    AppHaptics.light()
                    onSend()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSend ? AppTheme.accentForeground : AppTheme.mutedForeground)
                        .frame(width: AppTheme.touchMin, height: AppTheme.touchMin)
                        .background(canSend ? AppTheme.accent : AppTheme.surfaceActive, in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Envoyer")
                .accessibilityIdentifier(A11yID.Chat.send)
            }
        }
    }
}

/// Chrome composer : Liquid Glass iOS 26, fallback opaque si Reduce Transparency.
private struct ComposerGlassChrome: ViewModifier {
    let editing: Bool
    let reduceTransparency: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.radiusXl, style: .continuous)
    }

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content
                    .background(AppTheme.surfaceElevated, in: shape)
            } else {
                content
                    .glassEffect(
                        .regular.tint(AppTheme.surface.opacity(0.35)),
                        in: shape
                    )
            }
        }
        .overlay(
            shape.stroke(
                editing ? AppTheme.accent.opacity(0.4) : AppTheme.chromeStroke,
                lineWidth: editing ? 1.25 : 0.5
            )
        )
    }
}

/// Sheet d’options — reste ouverte pendant les changements (contrairement à Menu).
/// État local miroir pour feedback immédiat (ne pas attendre le réseau).
struct ChatToolsSheet: View {
    let chatMode: String
    let webSearchEnabled: Bool
    let selectedModelName: String
    let models: [ModelOptionDTO]
    let reasoningModes: [ReasoningModeDTO]
    let reasoningEffort: String
    let modelSwitching: Bool
    var thinkingEnabled: Bool = false
    var thinkingAvailable: Bool = false
    var toolChannel: ComposerToolChannel = .web
    /// `false` dans les assistants Mail / Files (canal imposé).
    var showsToolChannelPicker: Bool = true
    let onModeChange: (String) -> Void
    let onWebChange: (Bool) -> Void
    let onModelChange: (String) -> Void
    let onReasoningChange: (String) -> Void
    var onToggleThinking: (() -> Void)? = nil
    var onSelectToolChannel: ((ComposerToolChannel) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var localModel = ""
    @State private var localReasoning = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        AppHaptics.selection()
                        onModeChange(chatMode == "agent" ? "chat" : "agent")
                    } label: {
                        HStack(spacing: AppTheme.space12) {
                            Image(systemName: chatMode == "agent" ? "cpu.fill" : "bubble.left.and.bubble.right")
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mode")
                                    .foregroundStyle(AppTheme.foreground)
                                Text(chatMode == "agent" ? "Agent" : "Chat")
                                    .font(CNFont.caption)
                                    .foregroundStyle(AppTheme.mutedForeground)
                            }
                            Spacer()
                            Text(chatMode == "agent" ? "Passer en chat" : "Passer en agent")
                                .font(CNFont.caption)
                                .foregroundStyle(AppTheme.mutedForeground)
                        }
                    }
                    .listRowBackground(AppTheme.surface)

                    Button {
                        guard thinkingAvailable else { return }
                        AppHaptics.selection()
                        onToggleThinking?()
                    } label: {
                        HStack(spacing: AppTheme.space12) {
                            Image(systemName: thinkingEnabled ? "brain.fill" : "brain")
                                .foregroundStyle(thinkingAvailable ? AppTheme.secondary : AppTheme.mutedForeground)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Raisonnement")
                                    .foregroundStyle(
                                        thinkingAvailable ? AppTheme.foreground : AppTheme.mutedForeground
                                    )
                                Text(thinkingEnabled ? "Activé" : "Désactivé")
                                    .font(CNFont.caption)
                                    .foregroundStyle(AppTheme.mutedForeground)
                            }
                            Spacer()
                            Image(systemName: thinkingEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(thinkingEnabled ? AppTheme.secondary : AppTheme.mutedForeground)
                        }
                    }
                    .disabled(!thinkingAvailable)
                    .listRowBackground(AppTheme.surface)
                } header: {
                    Text("Contrôles rapides")
                }

                if showsToolChannelPicker {
                    Section {
                        ForEach(ComposerToolChannel.allCases) { channel in
                            Button {
                                AppHaptics.selection()
                                onSelectToolChannel?(channel)
                                if channel == .web {
                                    onWebChange(true)
                                } else if toolChannel == .web {
                                    onWebChange(false)
                                }
                            } label: {
                                HStack(spacing: AppTheme.space12) {
                                    Image(systemName: channel.systemImage)
                                        .foregroundStyle(AppTheme.secondary)
                                        .frame(width: 28)
                                    Text(channel.menuTitle)
                                        .foregroundStyle(AppTheme.foreground)
                                    Spacer()
                                    if toolChannel == channel {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(AppTheme.secondary)
                                    }
                                }
                            }
                            .listRowBackground(AppTheme.surface)
                        }
                    } header: {
                        Text("Canal d’outils")
                    } footer: {
                        Text("Mêmes options que les boutons à droite du composer.")
                    }
                }

                Section {
                    if modelSwitching {
                        HStack(spacing: AppTheme.space8) {
                            ProgressView().controlSize(.small)
                            Text("Changement de modèle…")
                                .foregroundStyle(AppTheme.muted)
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                    ForEach(models) { model in
                        Button {
                            localModel = model.id
                            AppHaptics.selection()
                            onModelChange(model.id)
                        } label: {
                            HStack {
                                Text(model.name)
                                    .foregroundStyle(AppTheme.foreground)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if localModel == model.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                        }
                        .disabled(modelSwitching && localModel != model.id)
                        .listRowBackground(AppTheme.surface)
                    }
                } header: {
                    Text("Modèle")
                }

                if !reasoningModes.isEmpty {
                    Section {
                        ForEach(reasoningModes) { mode in
                            Button {
                                localReasoning = mode.id
                                AppHaptics.selection()
                                onReasoningChange(mode.id)
                            } label: {
                                HStack {
                                    Text(mode.label ?? mode.id)
                                        .foregroundStyle(AppTheme.foreground)
                                    Spacer()
                                    if localReasoning == mode.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(AppTheme.accent)
                                    }
                                }
                            }
                            .listRowBackground(AppTheme.surface)
                        }
                    } header: {
                        Text("Raisonnement (détail)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.background)
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                        .fontWeight(.semibold)
                        .foregroundStyle(AppTheme.accent)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    KeyboardDismissButton()
                }
            }
            .onAppear {
                localModel = selectedModelName
                localReasoning = reasoningEffort
            }
            .onChange(of: selectedModelName) { _, v in localModel = v }
            .onChange(of: reasoningEffort) { _, v in localReasoning = v }
        }
    }
}

struct ScrollToBottomButton: View {
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let visualSize: CGFloat = 36
    private let hitSize: CGFloat = AppTheme.touchMin

    var body: some View {
        Button {
            AppHaptics.light()
            action()
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.foreground.opacity(0.9))
                .frame(width: visualSize, height: visualSize)
                .modifier(ScrollGlassChrome(reduceTransparency: reduceTransparency))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: hitSize, height: hitSize)
        .contentShape(Circle())
        .accessibilityLabel("Descendre")
    }
}

private struct ScrollGlassChrome: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content
                    .background(AppTheme.surfaceElevated.opacity(0.75), in: Circle())
            } else {
                content
                    .glassEffect(
                        .regular.tint(AppTheme.surface.opacity(0.14)),
                        in: Circle()
                    )
            }
        }
        .overlay(Circle().stroke(AppTheme.chromeStroke, lineWidth: 0.5))
    }
}

/// Barre d’actions produit persistante (au-dessus du chat) — jamais injectée comme messages.
struct PersistentProductActionsBar: View {
    let scope: ConversationScope
    var hasMailThread: Bool = false
    var hasDraft: Bool = false
    let onAction: (ChatScreen.QuickAction) -> Void

    private var actions: [(ChatScreen.QuickAction, String, String)] {
        if scope == .mail {
            // Brouillon ouvert : actions uniquement sur la carte (pas de barre redondante).
            if hasDraft {
                return []
            }
            if hasMailThread {
                return [
                    (.summarize, "Résumer", "text.alignleft"),
                    (.reply, "Répondre", "arrowshape.turn.up.left"),
                ]
            }
            // Assistant boîte mail (pas un fil) : pas de raccourcis — le chat suffit.
            return []
        }
        return [
            // Pas d’action « Explorer » — Files est déjà l’explorateur natif.
        ]
    }

    var body: some View {
        let items = actions
        if items.isEmpty {
            EmptyView()
        } else {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.0) { item in
                    Button {
                        AppHaptics.light()
                        onAction(item.0)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.2)
                                .font(.caption.weight(.semibold))
                            Text(item.1)
                                .font(.subheadline.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .foregroundStyle(AppTheme.foreground)
                        .background(AppTheme.surfaceElevated)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(AppTheme.chipStroke, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(AppTheme.surface.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.borderSubtle)
                .frame(height: 0.5)
        }
        .accessibilityIdentifier("assistant.productActions")
        }
    }
}

/// Empty hero Assistant (sans boutons — les actions sont dans PersistentProductActionsBar).
struct ContextualQuickActions: View {
    let scope: ConversationScope
    var hasMailThread: Bool = false
    let onAction: (ChatScreen.QuickAction) -> Void

    var body: some View {
        let _ = onAction
        VStack(spacing: AppTheme.space16) {
            Image(systemName: scope == .mail ? "envelope.open" : "folder")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(AppTheme.accent.opacity(0.9))
                .padding(.top, AppTheme.space16)
            Text(scope == .mail ? "Assistant Mail" : "Assistant Files")
                .font(CNFont.title)
                .foregroundStyle(AppTheme.foreground)
            Text(hasMailThread
                ? "Utilise les actions ci-dessus, ou pose une question."
                : (scope == .mail
                   ? "Pose une question sur ta boîte mail."
                   : "Pose une question pour commencer."))
                .font(CNFont.callout)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.space24)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, AppTheme.space24)
    }
}
