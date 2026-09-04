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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Chat.composer)
        .modifier(ComposerGlassChrome(editing: editing, reduceTransparency: reduceTransparency))
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
                        .regular.tint(AppTheme.accent.opacity(0.12)),
                        in: shape
                    )
            }
        }
        .overlay(
            shape.stroke(
                editing ? AppTheme.accent.opacity(0.55) : AppTheme.glassBorder.opacity(0.55),
                lineWidth: editing ? 1.5 : 1
            )
        )
    }
}

/// Sheet d’options — reste ouverte pendant les changements (contrairement à Menu).
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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Mode", selection: Binding(
                        get: { chatMode },
                        set: { onModeChange($0) }
                    )) {
                        Text("Chat").tag("chat")
                        Text("Agent").tag("agent")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("chat.mode.picker")
                    .listRowBackground(AppTheme.surface)

                    Toggle("Recherche web", isOn: Binding(
                        get: { webSearchEnabled },
                        set: { onWebChange($0) }
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
                            Text("Changement…")
                                .foregroundStyle(AppTheme.muted)
                        }
                        .listRowBackground(AppTheme.surface)
                    }
                    ForEach(models) { model in
                        Button {
                            onModelChange(model.id)
                        } label: {
                            HStack {
                                Text(model.name)
                                    .foregroundStyle(AppTheme.foreground)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                if selectedModelName == model.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                        }
                        .disabled(modelSwitching)
                        .listRowBackground(AppTheme.surface)
                    }
                } header: {
                    Text("Modèle")
                }

                if !reasoningModes.isEmpty {
                    Section {
                        ForEach(reasoningModes) { mode in
                            Button {
                                onReasoningChange(mode.id)
                            } label: {
                                HStack {
                                    Text(mode.label ?? mode.id)
                                        .foregroundStyle(AppTheme.foreground)
                                    Spacer()
                                    if reasoningEffort == mode.id {
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
        }
        .preferredColorScheme(.dark)
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

struct EmptyChatCanvas: View {
    let onSuggestion: (String) -> Void

    private let suggestions = [
        "Résume mes mails non lus",
        "Cherche un fichier sur le disque",
        "Qu’as-tu retenu sur moi ?",
    ]

    var body: some View {
        VStack(spacing: AppTheme.space24) {
            Spacer(minLength: AppTheme.space32)
            VStack(spacing: AppTheme.space12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(AppTheme.accent.opacity(0.9))
                    .accessibilityHidden(true)
                Text("Chatbot")
                    .font(CNFont.title)
                    .foregroundStyle(AppTheme.foreground)
                Text("Dis-moi ce dont tu as besoin.")
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.muted)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: AppTheme.space8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        AppHaptics.light()
                        onSuggestion(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(CNFont.body)
                            .foregroundStyle(AppTheme.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppTheme.space16)
                            .padding(.vertical, AppTheme.space12)
                            .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(suggestion)
                }
            }
            .padding(.horizontal, AppTheme.space24)

            Spacer(minLength: AppTheme.space16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
