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

    var onModeChange: ((String) -> Void)?
    var onWebChange: ((Bool) -> Void)?
    var onModelChange: ((String) -> Void)?
    var onReasoningChange: ((String) -> Void)?

    let onSend: () -> Void
    let onStop: () -> Void
    let onPickDoc: () -> Void
    var onCancelEdit: (() -> Void)? = nil

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.space8) {
            // Fermer collé au composer (au-dessus), pas flottant dans le canvas.
            if fieldFocused {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        fieldFocused = false
                        Keyboard.dismiss()
                    } label: {
                        Text("Fermer")
                            .font(CNFont.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .accessibilityLabel("Fermer le clavier")
                    .accessibilityIdentifier(A11yID.Chat.keyboardDismiss)
                }
                .padding(.horizontal, AppTheme.space4)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

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
                        .foregroundStyle(AppTheme.accent)
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
                                .tint(AppTheme.accent)
                        } else {
                            Image(systemName: "paperclip")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
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
        }
        .padding(.horizontal, AppTheme.space8)
        .padding(.vertical, AppTheme.space4)
        .modifier(ComposerGlassChrome(editing: editing, reduceTransparency: reduceTransparency))
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
                onModeChange: { onModeChange?($0) },
                onWebChange: { onWebChange?($0) },
                onModelChange: { onModelChange?($0) },
                onReasoningChange: { onReasoningChange?($0) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var sendOrStop: some View {
        Group {
            if isSending {
                Button {
                    AppHaptics.warning()
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
                    AppHaptics.medium()
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
                editing ? AppTheme.accent.opacity(0.4) : AppTheme.borderSubtle,
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
    let onModeChange: (String) -> Void
    let onWebChange: (Bool) -> Void
    let onModelChange: (String) -> Void
    let onReasoningChange: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var localMode: String = "chat"
    @State private var localWeb = false
    @State private var localModel = ""
    @State private var localReasoning = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Mode", selection: Binding(
                        get: { localMode },
                        set: { next in
                            localMode = next
                            AppHaptics.light()
                            onModeChange(next)
                        }
                    )) {
                        Text("Chat").tag("chat")
                        Text("Agent").tag("agent")
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(AppTheme.surface)

                    Toggle("Recherche web", isOn: Binding(
                        get: { localWeb },
                        set: { next in
                            localWeb = next
                            AppHaptics.light()
                            onWebChange(next)
                        }
                    ))
                    .tint(AppTheme.accent)
                    .listRowBackground(AppTheme.surface)
                } header: {
                    Text("Conversation")
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
                            AppHaptics.light()
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
                                AppHaptics.light()
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
                        Text("Raisonnement")
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
                localMode = chatMode
                localWeb = webSearchEnabled
                localModel = selectedModelName
                localReasoning = reasoningEffort
            }
            .onChange(of: chatMode) { _, v in localMode = v }
            .onChange(of: webSearchEnabled) { _, v in localWeb = v }
            .onChange(of: selectedModelName) { _, v in localModel = v }
            .onChange(of: reasoningEffort) { _, v in localReasoning = v }
        }
    }
}

struct ScrollToBottomButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            AppHaptics.light()
            action()
        } label: {
            Image(systemName: "arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.foreground)
                .frame(width: AppTheme.touchMin, height: AppTheme.touchMin)
                .background(AppTheme.surfaceElevated, in: Circle())
                .overlay(Circle().stroke(AppTheme.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Descendre")
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
            if hasDraft {
                return [
                    (.improve, "Modifier avec IA", "wand.and.stars"),
                    (.extractTasks, "Ajouter PJ", "paperclip"),
                    (.searchUnread, "Envoyer", "paperplane"),
                ]
            }
            if hasMailThread {
                return [
                    (.summarize, "Résumer", "text.alignleft"),
                    (.reply, "Répondre", "arrowshape.turn.up.left"),
                    (.extractTasks, "Extraire", "checklist"),
                ]
            }
            return [
                (.searchUnread, "Non lus", "envelope.badge"),
                (.draft, "Nouveau mail", "square.and.pencil"),
            ]
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
                        .overlay(Capsule().stroke(AppTheme.borderSubtle, lineWidth: 0.5))
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
                : "Utilise les actions ci-dessus pour commencer.")
                .font(CNFont.callout)
                .foregroundStyle(AppTheme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.space24)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, AppTheme.space24)
    }
}
