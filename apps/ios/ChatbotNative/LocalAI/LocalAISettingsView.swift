import SwiftUI

/// Politique UI (pas un second verrou) : décide si un bouton peut encore créer un Task.
/// `ModelExclusiveOperation` reste la source de vérité côté `LocalModelManager`.
enum LocalAISettingsActionGate {
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

/// Réglages « IA locale » — gestionnaire multi-modèles (sélection **explicite** uniquement).
struct LocalAISettingsView: View {
    @ObservedObject private var models = LocalModelManager.shared
    @ObservedObject private var execution = ExecutionModeStore.shared

    @State private var busyAction = false
    @State private var showTestSheet = false
    @State private var pendingLoadWarning: LocalModelDescriptor?
    @State private var confirmLoadExperimental = false

    private var mutationsDisabled: Bool {
        !LocalAISettingsActionGate.allowsNewMutationTask(
            busyAction: busyAction,
            exclusiveOperation: models.exclusiveOperation,
            state: models.state
        )
    }

    var body: some View {
        Section {
            executionPicker
            activeModelHeader
            if case .downloading(let p) = models.state {
                ProgressView(value: p)
                    .tint(AppTheme.accent)
            }
            if case .loading = models.state {
                ProgressView("Chargement…")
                    .tint(AppTheme.accent)
            }
            if case .unloading = models.state {
                ProgressView("Déchargement…")
                    .tint(AppTheme.accent)
            }
            if let err = models.lastError, !err.isEmpty {
                Text(humanLocalAIError(err))
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.danger)
            }
            installedModelsBlock
            availableModelsBlock
            HStack {
                Button("Tester") { showTestSheet = true }
                    .disabled(!models.isReady || mutationsDisabled)
            }
            .font(CNFont.callout.weight(.semibold))
        } header: {
            Text("IA locale")
        } footer: {
            Text(
                "Un seul modèle chargé à la fois. Qwen3.5 2B : installer la vision (mmproj) sans remplacer le GGUF texte. Un sideload IPA efface les GGUF du conteneur."
            )
        }
        .listRowBackground(AppTheme.surface)
        .sheet(isPresented: $showTestSheet) {
            LocalModelTestSheet()
        }
        .alert(
            "Modèle exigeant",
            isPresented: $confirmLoadExperimental
        ) {
            Button("Annuler", role: .cancel) { pendingLoadWarning = nil }
            Button("Charger quand même", role: .destructive) {
                if let model = pendingLoadWarning {
                    runSwitch(to: model)
                }
                pendingLoadWarning = nil
            }
        } message: {
            Text(pendingLoadWarning?.compatibilityNote
                ?? "Ce modèle peut être instable sur cet iPhone (mémoire).")
        }
    }

    private var preferenceBinding: Binding<ExecutionModePreference> {
        Binding(
            get: { execution.preference },
            set: { execution.setPreference($0) }
        )
    }

    private var executionPicker: some View {
        Group {
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
        }
    }

    private var activeModelHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Modèle local")
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.muted)
            Text(models.activeDescriptor.displayName)
                .font(CNFont.body.weight(.semibold))
            Text("\(models.activeDescriptor.quant) · \(models.activeDescriptor.expectedSizeLabel)")
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.mutedForeground)
            HStack(spacing: 6) {
                Circle()
                    .fill(models.isReady ? AppTheme.accent : AppTheme.muted)
                    .frame(width: 8, height: 8)
                Text(models.isReady ? "Chargé" : humanStateLabel(models.state))
                    .font(CNFont.caption.weight(.semibold))
                    .foregroundStyle(models.isReady ? AppTheme.accent : AppTheme.muted)
            }
            if models.activeDescriptor.recommended {
                Text(models.activeDescriptor.userFacingBlurb)
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.mutedForeground)
            }
        }
    }

    private var installedModelsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Modèles installés")
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.muted)
            let installed = models.installedModels
            if installed.isEmpty {
                Text("Aucun modèle installé.")
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.mutedForeground)
            } else {
                ForEach(installed) { model in
                    modelRow(model, installed: true)
                }
            }
        }
    }

    private var availableModelsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Disponibles")
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.muted)
            let available = LocalModelDescriptor.downloadable.filter { !models.isInstalled($0) }
            if available.isEmpty {
                Text("Tous les modèles disponibles sont installés.")
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.mutedForeground)
            } else {
                ForEach(available) { model in
                    modelRow(model, installed: false)
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: LocalModelDescriptor, installed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(models.activeModelId == model.id && models.isReady ? "✓" : "○")
                    .font(CNFont.callout.weight(.semibold))
                    .foregroundStyle(models.activeModelId == model.id && models.isReady ? AppTheme.accent : AppTheme.muted)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(CNFont.callout.weight(.semibold))
                    Text(model.userFacingBlurb)
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                    Text(model.expectedSizeLabel)
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                    if let mmproj = model.mmproj, installed {
                        visionProjectorRow(model, mmproj: mmproj)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: AppTheme.space8) {
                if installed {
                    if models.activeModelId == model.id, models.isReady {
                        Button {
                            guard beginUIAction() else { return }
                            Task {
                                defer { busyAction = false }
                                await models.unload()
                                execution.refreshDerived()
                            }
                        } label: {
                            localAIActionLabel("Décharger")
                        }
                        .buttonStyle(.borderless)
                        .disabled(mutationsDisabled)
                    } else {
                        Button {
                            requestLoad(model)
                        } label: {
                            localAIActionLabel("Charger")
                        }
                        .buttonStyle(.borderless)
                        .tint(AppTheme.accent)
                        .disabled(
                            mutationsDisabled
                                || !LocalInferenceEngine.isLlamaRuntimeAvailable
                        )
                    }
                    Button {
                        guard beginUIAction() else { return }
                        Task {
                            defer { busyAction = false }
                            await models.deleteModel(model)
                            execution.refreshDerived()
                        }
                    } label: {
                        localAIActionLabel("Supprimer")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.danger)
                    .disabled(mutationsDisabled)
                } else if model.isDownloadable {
                    Button {
                        guard beginUIAction() else { return }
                        Task {
                            defer { busyAction = false }
                            await models.install(model: model)
                        }
                    } label: {
                        localAIActionLabel("Télécharger")
                    }
                    .buttonStyle(.borderless)
                    .tint(AppTheme.accent)
                    .disabled(mutationsDisabled)
                }
            }
            .font(CNFont.callout.weight(.semibold))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func visionProjectorRow(_ model: LocalModelDescriptor, mmproj: LocalMmprojDescriptor) -> some View {
        let installedVision = models.isVisionProjectorInstalled(model)
        VStack(alignment: .leading, spacing: 4) {
            Text("Vision (mmproj \(mmproj.quant) · \(mmproj.expectedSizeLabel))")
                .font(CNFont.caption.weight(.semibold))
            Text(mmproj.compatibilityNote)
                .font(CNFont.caption2)
                .foregroundStyle(AppTheme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            if models.visionProjectorBusy, models.activeModelId == model.id {
                ProgressView(value: models.visionProjectorProgress)
                    .tint(AppTheme.accent)
            }
            HStack(spacing: AppTheme.space8) {
                if installedVision {
                    Text("Installé")
                        .font(CNFont.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    Button {
                        guard beginUIAction() else { return }
                        Task {
                            defer { busyAction = false }
                            await models.deleteVisionProjector(for: model)
                        }
                    } label: {
                        localAIActionLabel("Retirer vision")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(AppTheme.danger)
                    .disabled(mutationsDisabled || models.visionProjectorBusy)
                } else {
                    Button {
                        guard beginUIAction() else { return }
                        Task {
                            defer { busyAction = false }
                            await models.installVisionProjector(for: model)
                        }
                    } label: {
                        localAIActionLabel("Installer vision")
                    }
                    .buttonStyle(.borderless)
                    .tint(AppTheme.accent)
                    .disabled(mutationsDisabled || models.visionProjectorBusy)
                }
            }
        }
    }

    private func humanStateLabel(_ state: LocalModelInstallState) -> String {
        switch state {
        case .ready: return "Chargé"
        case .downloading: return "Téléchargement…"
        case .verifying: return "Vérification…"
        case .loading: return "Chargement…"
        case .unloading: return "Déchargement…"
        case .generating: return "Génération…"
        case .installed: return "Installé"
        case .notInstalled: return "Non chargé"
        case .failed: return "Erreur"
        }
    }

    private func humanLocalAIError(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("disk") || lower.contains("espace") {
            return "Espace disque insuffisant pour ce modèle."
        }
        if lower.contains("network") || lower.contains("offline") || lower.contains("internet") {
            return "Téléchargement impossible (réseau)."
        }
        if lower.contains("memory") || lower.contains("jetsam") || lower.contains("oom") {
            return "Mémoire insuffisante pour charger ce modèle."
        }
        if raw.count > 140 {
            return "Le modèle n’a pas pu être chargé. Réessaie."
        }
        return raw
    }

    private func requestLoad(_ model: LocalModelDescriptor) {
        switch model.compatibilityIPhone14Plus {
        case .recommended:
            runSwitch(to: model)
        case .experimental, .notRecommended:
            pendingLoadWarning = model
            confirmLoadExperimental = true
        }
    }

    private func runSwitch(to model: LocalModelDescriptor) {
        guard beginUIAction() else { return }
        Task {
            defer { busyAction = false }
            await models.switchToModel(model)
            execution.refreshDerived()
        }
    }

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

    private func localAIActionLabel(_ title: String) -> some View {
        Text(title)
            .padding(.horizontal, AppTheme.space8)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
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
                Text("Génère une courte réponse pour vérifier \(models.activeDescriptor.displayName).")
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.mutedForeground)

                if running {
                    ProgressView("Génération…")
                }
                if let errorText {
                    Text(errorText).foregroundStyle(AppTheme.danger).font(CNFont.caption)
                }
                ScrollView {
                    Text(output.isEmpty ? "—" : output)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(CNFont.body)
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Test local")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        Task { await LocalInferenceEngine.shared.cancel() }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lancer") {
                        Task { await runTest() }
                    }
                    .disabled(!models.isReady || running)
                }
                if models.isVisionProjectorInstalled {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Vision") {
                            Task { await runVisionTest() }
                        }
                        .disabled(!models.isReady || running)
                    }
                }
            }
        }
    }

    private func runTest() async {
        running = true
        errorText = nil
        output = ""
        defer { running = false }
        let result = await LocalModelBenchmarkRunner.runPrompt(
            label: "smoke",
            prompt: "Dis bonjour en une courte phrase.",
            maxTokens: 64
        )
        output = ChatMLPromptBuilder.stripControlTokens(result.outputPreview)
        if !result.success {
            errorText = result.errorMessage
        }
    }

    private func runVisionTest() async {
        running = true
        errorText = nil
        output = ""
        defer { running = false }
        guard let jpeg = LocalVision.solidColorJPEG(red: 0.86, green: 0.12, blue: 0.12) else {
            errorText = "Impossible de créer l’image de test."
            return
        }
        do {
            let text = try await LocalAIRuntime.shared.generateStream(
                system: "Tu es un assistant visuel. Réponds en une phrase.",
                messages: [
                    LLMChatMessage(role: .user, content: "Quelle couleur domine cette image ?"),
                ],
                maxTokens: 64,
                images: [jpeg],
                onToken: { token in
                    output += token
                }
            )
            output = ChatMLPromptBuilder.stripControlTokens(text)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Benchmark sheet

private struct LocalModelBenchmarkSheet: View {
    @ObservedObject private var models = LocalModelManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var results: [LocalModelBenchmarkResult] = []
    @State private var running = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Modèle : \(models.activeDescriptor.displayName) (\(models.activeDescriptor.quant))")
                    Text("Device : \(LocalModelBenchmarkSuite.deviceModelLabel)")
                    Text("App : \(LocalModelBenchmarkSuite.appVersionLabel)")
                }
                Section("Résultats") {
                    if results.isEmpty, !running {
                        Text("Lance la suite pour mesurer TTFT / tok/s.")
                            .foregroundStyle(AppTheme.mutedForeground)
                    }
                    ForEach(results) { r in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.promptLabel).font(.headline)
                            Text(r.success ? "OK" : (r.errorMessage ?? "Échec"))
                                .foregroundStyle(r.success ? AppTheme.accent : AppTheme.danger)
                            if let backend = r.backendEffective {
                                Text("backend=\(backend) gpuLayers=\(r.nGpuLayersConfigured.map(String.init) ?? "?") ctx=\(r.nCtx.map(String.init) ?? "?")")
                                    .font(CNFont.caption)
                                    .foregroundStyle(AppTheme.mutedForeground)
                            }
                            if let ttft = r.timeToFirstTokenMs {
                                Text(String(format: "TTFT %.0f ms", ttft))
                            }
                            if let promptTps = r.promptTokensPerSecond, let promptMs = r.promptEvalMs {
                                Text(String(format: "Prompt %.0f ms · %.1f tok/s (%d)", promptMs, promptTps, r.promptTokens))
                            }
                            if let tps = r.tokensPerSecond {
                                Text(String(format: "Gen %.1f tok/s · %d tokens", tps, r.generatedTokens))
                            }
                            Text(r.outputPreview)
                                .font(CNFont.caption)
                                .foregroundStyle(AppTheme.mutedForeground)
                        }
                    }
                }
            }
            .navigationTitle("Benchmark")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        Task { await LocalInferenceEngine.shared.cancel() }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(running ? "…" : "Lancer") {
                        Task { await runSuite() }
                    }
                    .disabled(running || !models.isReady)
                }
            }
        }
    }

    private func runSuite() async {
        running = true
        defer { running = false }
        results = []
        for item in LocalModelBenchmarkSuite.prompts {
            let r = await LocalModelBenchmarkRunner.runPrompt(label: item.id, prompt: item.text)
            results.append(r)
        }
    }
}

