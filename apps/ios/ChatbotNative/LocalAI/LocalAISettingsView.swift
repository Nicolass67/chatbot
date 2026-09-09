import SwiftUI

/// Politique UI (pas un second verrou) : décide si un bouton peut encore créer un Task.
/// `ModelExclusiveOperation` reste la source de vérité côté `LocalModelManager`.
enum LocalAISettingsActionGate {
    /// `busyAction` doit déjà être consulté/posé **avant** `Task { }` par l’appelant.
    static func allowsNewMutationTask(
        busyAction: Bool,
        exclusiveOperation: ModelExclusiveOperation?,
        state: LocalModelInstallState
    ) -> Bool {
        if busyAction { return false }
        if exclusiveOperation != nil { return false }
        switch state {
        case .loading, .unloading, .generating:
            return false
        default:
            return true
        }
    }
}

/// Section Réglages « IA locale » — téléchargement, chargement, test du modèle on-device.
struct LocalAISettingsView: View {
    @ObservedObject private var models = LocalModelManager.shared
    @ObservedObject private var execution = ExecutionModeStore.shared

    @State private var showTestSheet = false
    @State private var busyAction = false

    /// Désactive les boutons mutatifs : busy UI + exclusive manager + états incompatibles.
    private var mutationsDisabled: Bool {
        !LocalAISettingsActionGate.allowsNewMutationTask(
            busyAction: busyAction,
            exclusiveOperation: models.exclusiveOperation,
            state: models.state
        )
    }

    var body: some View {
        Section {
            modelInfoRows
            stateRow
            if case .downloading(let p) = models.state {
                ProgressView(value: p)
                    .tint(AppTheme.accent)
                    .accessibilityLabel("Progression du téléchargement")
            }
            if case .loading = models.state {
                ProgressView("Chargement du modèle en mémoire…")
                    .tint(AppTheme.accent)
            }
            if case .unloading = models.state {
                ProgressView("Déchargement…")
                    .tint(AppTheme.accent)
            }
            if let err = models.lastError, !err.isEmpty {
                Text(err)
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.danger)
            }
            actionButtons
            Picker("Exécution", selection: preferenceBinding) {
                ForEach(ExecutionModePreference.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Text(execution.preference.helpText)
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.muted)
            Text(execution.statusLabel)
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.mutedForeground)
        } header: {
            Text("IA locale")
        } footer: {
            Text(
                "Le modèle tourne sur l’iPhone. Après Installer, attendez « Installé » (fichier réel présent) puis Charger. Un sideload / réinstall IPA recrée le conteneur app et efface le GGUF — il faut alors réinstaller le modèle."
            )
        }
        .listRowBackground(AppTheme.surface)
        .sheet(isPresented: $showTestSheet) {
            LocalModelTestSheet()
        }
    }

    private var preferenceBinding: Binding<ExecutionModePreference> {
        Binding(
            get: { execution.preference },
            set: { execution.setPreference($0) }
        )
    }

    private var modelInfoRows: some View {
        Group {
            LabeledContent("Modèle", value: models.activeDescriptor.displayName)
            LabeledContent("Quantification", value: models.activeDescriptor.quant)
            LabeledContent("Taille attendue", value: models.activeDescriptor.expectedSizeLabel)
            LabeledContent(
                "Taille réelle",
                value: models.actualFileSize > 0
                    ? String(format: "%.0f Mo", Double(models.actualFileSize) / 1_048_576.0)
                    : "—"
            )
            LabeledContent("Fichier présent", value: models.actualFileExists ? "Oui" : "Non")
            LabeledContent("Fichier lisible", value: models.actualFileIsReadable ? "Oui" : "Non")
            LabeledContent(
                "Metal",
                value: models.isMetalAvailable ? "Disponible" : "Indisponible (simulateur)"
            )
            LabeledContent(
                "Runtime llama",
                value: LocalInferenceEngine.isLlamaRuntimeAvailable ? "Lié" : "Non lié (stub)"
            )
        }
    }

    private var stateRow: some View {
        LabeledContent("État", value: models.state.statusLabel)
    }

    /// Pose `busyAction` synchrone avant tout `Task` — empêche un 2ᵉ Task avant le prochain frame.
    @discardableResult
    private func beginUIAction() -> Bool {
        guard LocalAISettingsActionGate.allowsNewMutationTask(
            busyAction: busyAction,
            exclusiveOperation: models.exclusiveOperation,
            state: models.state
        ) else { return false }
        busyAction = true
        return true
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: AppTheme.space8) {
            if case .downloading = models.state {
                Button("Annuler") {
                    models.cancelDownload()
                }
                .foregroundStyle(AppTheme.danger)
            } else if !models.isInstalled {
                Button("Installer") {
                    guard beginUIAction() else { return }
                    Task {
                        defer { busyAction = false }
                        await models.install()
                    }
                }
                .disabled(!models.activeDescriptor.isDownloadable || mutationsDisabled)
                .tint(AppTheme.accent)
            } else {
                Button("Supprimer") {
                    guard beginUIAction() else { return }
                    Task {
                        defer { busyAction = false }
                        await models.deleteModel()
                    }
                }
                .foregroundStyle(AppTheme.danger)
                .disabled(mutationsDisabled)
            }

            Spacer()

            if models.isInstalled {
                if models.isReady {
                    Button("Décharger") {
                        guard beginUIAction() else { return }
                        Task {
                            defer { busyAction = false }
                            await models.unload()
                            execution.refreshDerived()
                        }
                    }
                    .disabled(mutationsDisabled)
                } else {
                    Button("Charger") {
                        guard beginUIAction() else { return }
                        Task {
                            defer { busyAction = false }
                            LocalModelFileAudit.snapshotFS(
                                point: "D-charger-button",
                                finalPath: models.modelFilePath
                            )
                            await models.loadIntoEngine()
                            execution.refreshDerived()
                        }
                    }
                    .disabled(
                        mutationsDisabled
                            || !LocalInferenceEngine.isLlamaRuntimeAvailable
                    )
                    .tint(AppTheme.accent)
                }

                Button("Tester") {
                    showTestSheet = true
                }
                .disabled(!models.isReady || mutationsDisabled)
                .tint(AppTheme.accent)
            }
        }
        .font(CNFont.callout.weight(.semibold))
    }
}

// MARK: - Test sheet

private struct LocalModelTestSheet: View {
    @ObservedObject private var models = LocalModelManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var output = ""
    @State private var running = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.space16) {
                Text("Génère une courte réponse pour vérifier le modèle local (déjà chargé).")
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.mutedForeground)

                if running {
                    ProgressView("Génération…")
                        .tint(AppTheme.accent)
                }

                ScrollView {
                    Text(output.isEmpty ? "—" : output)
                        .font(CNFont.body)
                        .foregroundStyle(AppTheme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .padding(AppTheme.space12)
                .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))

                if let errorText {
                    Text(errorText)
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.danger)
                }

                Spacer()
            }
            .padding(AppTheme.space16)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Tester le modèle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        Task { await LocalInferenceEngine.shared.cancel() }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(running ? "Stop" : "Lancer") {
                        if running {
                            Task { await LocalInferenceEngine.shared.cancel() }
                        } else {
                            Task { await runTest() }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!models.isReady && !running)
                }
            }
        }
        .interactiveDismissDisabled(running)
    }

    private func runTest() async {
        errorText = nil
        output = ""
        guard models.isReady else {
            errorText = LocalInferenceError.notLoaded.localizedDescription
            return
        }
        running = true
        models.markGenerating(true)
        defer {
            running = false
            models.markGenerating(false)
        }

        let provider = LocalLLMProvider(promptKind: .conversation)
        let messages = [
            LLMChatMessage(role: .user, content: "Dis bonjour en une phrase courte."),
        ]
        do {
            for try await token in provider.stream(messages: messages, systemPrompt: nil, maxTokens: 64) {
                output += token
            }
            let metrics = await LocalInferenceEngine.shared.lastMetrics
            if let tps = metrics.tokensPerSecond {
                errorText = nil
                output += String(format: "\n\n— %.1f tok/s", tps)
            }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

#Preview {
    List {
        LocalAISettingsView()
    }
}
