import SwiftUI

/// Section Réglages « IA locale » — téléchargement, chargement, test du modèle on-device.
struct LocalAISettingsView: View {
    @ObservedObject private var models = LocalModelManager.shared
    @ObservedObject private var execution = ExecutionModeStore.shared

    @State private var showTestSheet = false
    @State private var busyAction = false

    var body: some View {
        Section {
            modelInfoRows
            stateRow
            if case .downloading(let p) = models.state {
                ProgressView(value: p)
                    .tint(AppTheme.accent)
                    .accessibilityLabel("Progression du téléchargement")
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
                "Le modèle tourne sur l’iPhone (Metal). Il est indépendant de LM Studio sur le PC — aucune bascule automatique du modèle distant."
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
            LabeledContent("Taille", value: models.activeDescriptor.expectedSizeLabel)
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
                    Task {
                        busyAction = true
                        defer { busyAction = false }
                        await models.install()
                    }
                }
                .disabled(!models.activeDescriptor.isDownloadable || busyAction)
                .tint(AppTheme.accent)
            } else {
                Button("Supprimer") {
                    Task {
                        busyAction = true
                        defer { busyAction = false }
                        await models.deleteModel()
                    }
                }
                .foregroundStyle(AppTheme.danger)
                .disabled(busyAction)
            }

            Spacer()

            if models.isInstalled {
                if models.isReady {
                    Button("Décharger") {
                        Task {
                            busyAction = true
                            defer { busyAction = false }
                            await models.unload()
                            execution.refreshDerived()
                        }
                    }
                    .disabled(busyAction)
                } else {
                    Button("Charger") {
                        Task {
                            busyAction = true
                            defer { busyAction = false }
                            await models.loadIntoEngine()
                            execution.refreshDerived()
                        }
                    }
                    .disabled(busyAction || !LocalInferenceEngine.isLlamaRuntimeAvailable)
                    .tint(AppTheme.accent)
                }

                Button("Tester") {
                    showTestSheet = true
                }
                .disabled(!models.isReady && !models.isInstalled)
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
                Text("Génère une courte réponse pour vérifier le modèle local.")
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
                }
            }
            .task {
                if !models.isReady, models.isInstalled {
                    await models.loadIntoEngine()
                }
            }
        }
    }

    private func runTest() async {
        errorText = nil
        output = ""
        running = true
        models.markGenerating(true)
        defer {
            running = false
            models.markGenerating(false)
        }

        if !models.isReady {
            await models.loadIntoEngine()
            guard models.isReady else {
                errorText = models.lastError ?? LocalInferenceError.notAvailable.localizedDescription
                return
            }
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
