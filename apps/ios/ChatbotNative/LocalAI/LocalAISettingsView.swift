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

    @State private var showTestSheet = false
    @State private var showBenchmarkSheet = false
    @State private var busyAction = false
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
            installedModelsBlock
            availableModelsBlock
            catalogHintsBlock
            HStack {
                Button("Tester") { showTestSheet = true }
                    .disabled(!models.isReady || mutationsDisabled)
                Button("Benchmark") { showBenchmarkSheet = true }
                    .disabled(!models.isReady || mutationsDisabled)
            }
            .font(CNFont.callout.weight(.semibold))
        } header: {
            Text("IA locale")
        } footer: {
            Text(
                "Un seul modèle chargé à la fois. Le changement de modèle est toujours manuel. Un sideload IPA efface les GGUF du conteneur."
            )
        }
        .listRowBackground(AppTheme.surface)
        .sheet(isPresented: $showTestSheet) {
            LocalModelTestSheet()
        }
        .sheet(isPresented: $showBenchmarkSheet) {
            LocalModelBenchmarkSheet()
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
            Text("Modèle actif")
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.muted)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(models.activeDescriptor.displayName)
                        .font(CNFont.body.weight(.semibold))
                    Text("\(models.activeDescriptor.quant) · \(models.activeDescriptor.expectedSizeLabel) · \(models.activeDescriptor.estimatedRAMLabel)")
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.mutedForeground)
                }
                Spacer()
                Text(models.isReady ? "Chargé" : models.state.statusLabel)
                    .font(CNFont.caption.weight(.semibold))
                    .foregroundStyle(models.isReady ? AppTheme.accent : AppTheme.muted)
            }
            LabeledContent("Metal", value: models.isMetalAvailable ? "Disponible" : "Indisponible")
            LabeledContent(
                "Runtime llama",
                value: LocalInferenceEngine.isLlamaRuntimeAvailable ? "Lié" : "Non lié (stub)"
            )
            InferenceDiagnosticsLine()
        }
    }

    private var installedModelsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Installés")
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.muted)
            let installed = models.installedModels
            if installed.isEmpty {
                Text("Aucun modèle installé — télécharge Qwen3 1.7B pour commencer.")
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
            Text("Disponibles au téléchargement")
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.muted)
            ForEach(LocalModelDescriptor.downloadable.filter { !models.isInstalled($0) }) { model in
                modelRow(model, installed: false)
            }
        }
    }

    private var catalogHintsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Catalogue (pas encore téléchargeable)")
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.muted)
            ForEach(LocalModelDescriptor.catalog.filter { !$0.isDownloadable }) { model in
                HStack(alignment: .top) {
                    compatibilityBadge(model.compatibilityIPhone14Plus)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName)
                            .font(CNFont.callout.weight(.medium))
                        Text(model.compatibilityNote)
                            .font(CNFont.caption2)
                            .foregroundStyle(AppTheme.mutedForeground)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func modelRow(_ model: LocalModelDescriptor, installed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                compatibilityBadge(model.compatibilityIPhone14Plus)
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(model.displayName)
                            .font(CNFont.callout.weight(.semibold))
                        if models.activeModelId == model.id, models.isReady {
                            Text("Chargé")
                                .font(CNFont.caption2.weight(.bold))
                                .foregroundStyle(AppTheme.accent)
                        }
                    }
                    Text("\(model.quant) · \(model.expectedSizeLabel) · \(model.estimatedRAMLabel)")
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                    Text(model.compatibilityNote)
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
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

    private func compatibilityBadge(_ level: LocalModelCompatibility) -> some View {
        Image(systemName: level.symbolName)
            .foregroundStyle({
                switch level {
                case .recommended: return AppTheme.accent
                case .experimental: return Color.orange
                case .notRecommended: return AppTheme.danger
                }
            }())
            .accessibilityLabel(level.label)
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

/// Affiche le dernier snapshot de load (Metal réel vs demandé).
private struct InferenceDiagnosticsLine: View {
    @State private var line: String = "—"

    var body: some View {
        Text(line)
            .font(CNFont.caption2)
            .foregroundStyle(AppTheme.mutedForeground)
            .task {
                if let diag = await LocalInferenceEngine.shared.lastLoadDiagnostics {
                    line = diag.summaryLine
                } else {
                    let infer = LocalModelManager.shared.activeDescriptor.executionProfile.inference
                    line = "Pas encore chargé — config prévue: metal=\(infer.preferMetal) ngl=\(infer.nGpuLayers) ctx=\(infer.nCtx) batch=\(infer.nBatch)/\(infer.nUbatch)"
                }
            }
    }
}
