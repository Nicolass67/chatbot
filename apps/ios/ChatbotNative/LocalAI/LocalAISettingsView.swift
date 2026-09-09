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
        Group {
        Section {
            executionPicker
            currentModelCard
        } header: {
            Text("IA locale")
        } footer: {
            Text("Un seul modèle est chargé en mémoire. Télécharger un modèle ne l’active pas tout seul — appuie sur Utiliser.")
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
            Button("Utiliser quand même", role: .destructive) {
                if let model = pendingLoadWarning {
                    runSwitch(to: model)
                }
                pendingLoadWarning = nil
            }
        } message: {
            Text("Ce modèle peut être instable sur cet iPhone. Le modèle actuel n’est changé que si tu confirmes.")
        }

        Section {
            let installed = LocalModelDescriptor.userFacingCatalog.filter { models.isInstalled($0) }
            if installed.isEmpty {
                Text("Aucun modèle installé pour le moment.")
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.mutedForeground)
            } else {
                ForEach(installed) { model in
                    modelCard(model)
                }
            }
        } header: {
            Text("Mes modèles")
        }
        .listRowBackground(AppTheme.surface)

        Section {
            let available = LocalModelDescriptor.userFacingCatalog.filter { $0.isDownloadable && !models.isInstalled($0) }
            if available.isEmpty {
                Text("Tous les modèles disponibles sont installés.")
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.mutedForeground)
            } else {
                ForEach(available) { model in
                    modelCard(model)
                }
            }
        } header: {
            Text("Modèles disponibles")
        } footer: {
            Text("Une réinstallation de l’app peut supprimer les fichiers téléchargés.")
        }
        .listRowBackground(AppTheme.surface)
        }
    }

    private var textInstallCaption: String {
        let name = LocalModelDescriptor.descriptor(id: models.textInstallModelId ?? "")?.displayName
            ?? "modèle"
        return "Téléchargement de \(name)"
    }

    private var preferenceBinding: Binding<ExecutionModePreference> {
        Binding(
            get: { execution.preference },
            set: { execution.setPreference($0) }
        )
    }

    private var executionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Exécution", selection: preferenceBinding) {
                ForEach(ExecutionModePreference.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Text(execution.preference.helpText)
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.muted)
        }
    }

    private var currentModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: models.isReady ? "checkmark.seal.fill" : "cpu")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Modèle actuel")
                        .font(CNFont.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedForeground)
                    Text(models.activeDescriptor.displayName)
                        .font(CNFont.body.weight(.semibold))
                    Text(models.isReady ? "Installé · Actif" : humanStateLabel(models.state))
                        .font(CNFont.caption.weight(.semibold))
                        .foregroundStyle(models.isReady ? AppTheme.accent : AppTheme.muted)
                    Text(models.activeDescriptor.userFacingBlurb)
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            if models.textInstallBusy {
                VStack(alignment: .leading, spacing: 8) {
                    Text(textInstallCaption)
                        .font(CNFont.caption.weight(.semibold))
                    ProgressView(value: models.textInstallProgress)
                        .tint(AppTheme.accent)
                    HStack {
                        Text("\(Int((models.textInstallProgress * 100).rounded())) %")
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.muted)
                        Spacer()
                        Button("Annuler") {
                            models.cancelDownload()
                        }
                        .font(CNFont.callout.weight(.semibold))
                        .frame(minHeight: 44)
                    }
                }
            }
            if case .loading = models.state {
                ProgressView("Chargement du modèle…")
                    .tint(AppTheme.accent)
            }
            if case .unloading = models.state {
                ProgressView("Déchargement…")
                    .tint(AppTheme.accent)
            }
            if let err = models.lastError, !err.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text(humanLocalAIError(err))
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Réessayer") {
                        requestLoad(models.activeDescriptor)
                    }
                    .font(CNFont.callout.weight(.semibold))
                    .frame(minHeight: 44)
                    .disabled(mutationsDisabled)
                }
            }

            if models.isReady {
                Button("Tester") { showTestSheet = true }
                    .font(CNFont.callout.weight(.semibold))
                    .frame(minHeight: 44)
                    .disabled(mutationsDisabled)
            }
        }
        .padding(.vertical, 4)
    }

    private func modelCard(_ model: LocalModelDescriptor) -> some View {
        let installed = models.isInstalled(model)
        let isActive = models.activeModelId == model.id && models.isReady
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isActive ? "checkmark.circle.fill" : (installed ? "checkmark.circle" : "arrow.down.circle"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isActive ? AppTheme.accent : AppTheme.muted)
                    .frame(width: 28, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(model.displayName)
                            .font(CNFont.callout.weight(.semibold))
                        if model.recommended {
                            Text("Recommandé")
                                .font(CNFont.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.accent.opacity(0.12), in: Capsule())
                        }
                    }
                    Text(model.userFacingBlurb)
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.mutedForeground)
                    Text("~ \(model.userFacingTextSizeLabel)")
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                    if isActive {
                        Text("Modèle actif")
                            .font(CNFont.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    } else if installed {
                        Text("Installé")
                            .font(CNFont.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.muted)
                    }
                    if models.isInstallingText(model) {
                        ProgressView(value: models.textInstallProgress)
                            .tint(AppTheme.accent)
                    }
                    if model.mmproj != nil, installed {
                        visionProjectorRow(model)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: AppTheme.space8) {
                if installed {
                    if !isActive {
                        Button {
                            requestLoad(model)
                        } label: {
                            localAIActionLabel("Utiliser")
                        }
                        .buttonStyle(.borderedProminent)
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
                    .buttonStyle(.bordered)
                    .foregroundStyle(AppTheme.danger)
                    .disabled(mutationsDisabled || models.isInstallingText(model))
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
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(mutationsDisabled || models.textInstallBusy)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.displayName)
    }

    @ViewBuilder
    private func visionProjectorRow(_ model: LocalModelDescriptor) -> some View {
        let installedVision = models.isVisionProjectorInstalled(model)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Vision")
                    .font(CNFont.caption.weight(.semibold))
                if installedVision {
                    Text("Installée")
                        .font(CNFont.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                } else {
                    Text("Non installée")
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                }
            }
            if models.isInstallingVision(model) {
                ProgressView(value: models.visionProjectorProgress)
                    .tint(AppTheme.accent)
            }
            HStack(spacing: AppTheme.space8) {
                if installedVision {
                    Button {
                        guard beginUIAction() else { return }
                        Task {
                            defer { busyAction = false }
                            await models.deleteVisionProjector(for: model)
                        }
                    } label: {
                        localAIActionLabel("Retirer")
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
                        localAIActionLabel("Installer la vision")
                    }
                    .buttonStyle(.borderless)
                    .tint(AppTheme.accent)
                    .disabled(mutationsDisabled || models.visionProjectorBusy || models.textInstallBusy)
                }
            }
        }
    }

    private func humanStateLabel(_ state: LocalModelInstallState) -> String {
        switch state {
        case .ready: return "Actif"
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
        if lower.contains("memory") || lower.contains("jetsam") || lower.contains("oom")
            || lower.contains("mémoire insuffisante") {
            return "Mémoire insuffisante pour charger ce modèle. Qwen3.5 2B reste le profil recommandé."
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
    @State private var gdnText = ""
    @State private var abRunning = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.space16) {
                Text("Génère une courte réponse pour vérifier \(models.activeDescriptor.displayName).")
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.mutedForeground)

                if running {
                    ProgressView("Génération…")
                }
                if abRunning {
                    ProgressView("A/B threads 2 vs 4… (plusieurs minutes)")
                }
                if !gdnText.isEmpty {
                    Text(gdnText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
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
                    .disabled(!models.isReady || running || abRunning)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("A/B 2/4") {
                        Task { await runThreadAB() }
                    }
                    .disabled(!models.isReady || running || abRunning)
                }
                if models.isVisionProjectorInstalled {
                    ToolbarItem(placement: .automatic) {
                        Button("Vision") {
                            Task { await runVisionTest() }
                        }
                        .disabled(!models.isReady || running || abRunning)
                    }
                }
            }
            .task { await refreshGdn() }
        }
    }

    private func refreshGdn() async {
        if let gdn = await LocalInferenceEngine.shared.lastLoadDiagnostics?.gdn {
            gdnText = gdn.explicitReport
        }
    }

    private func runThreadAB() async {
        abRunning = true
        errorText = nil
        defer { abRunning = false }
        let report = await LocalThreadABBenchmark.runIsolated(source: "settings-tester")
        gdnText = report.gdn.explicitReport + "\n\n" + report.explicitSummary
        output = report.explicitSummary
        if report.runs.filter({ !$0.warmup }).isEmpty {
            errorText = "Aucune mesure — modèle chargé ?"
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
            output = LocalChatTemplate.stripControlTokens(text, profile: models.activeRuntimeProfile)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Comparison sheet (debug)

private struct LocalModelComparisonSheet: View {
    @ObservedObject private var models = LocalModelManager.shared
    @ObservedObject private var store = LocalModelComparisonStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var running = false
    @State private var thinkingEnabled = false
    @State private var current: [LocalModelComparisonResult] = []

    private var qwenId: String { "qwen35-2b-q4_k_m" }
    private var gemmaId: String { "gemma4-e2b-it-q4_0" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Les tests tournent sur \(models.activeDescriptor.displayName), déjà chargé. Aucun changement automatique de modèle : pour comparer, appuie sur Utiliser dans Réglages, puis relance.")
                    Toggle("Mode réflexion (Gemma)", isOn: $thinkingEnabled)
                    if running {
                        ProgressView("Tests en cours…")
                    }
                }
                Section("Dernière série — \(models.activeDescriptor.displayName)") {
                    if current.isEmpty, store.results(for: models.activeModelId).isEmpty {
                        Text("Lance la suite pour mesurer TTFT / tok/s / qualité.")
                            .foregroundStyle(AppTheme.mutedForeground)
                    }
                    ForEach(current.isEmpty ? store.results(for: models.activeModelId) : current) { r in
                        resultRow(r)
                    }
                }
                Section("Qwen3.5 2B") {
                    comparisonSummary(modelId: qwenId)
                }
                Section("Gemma 4 E2B") {
                    comparisonSummary(modelId: gemmaId)
                }
            }
            .navigationTitle("Comparer les modèles")
            .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private func comparisonSummary(modelId: String) -> some View {
        let rows = store.results(for: modelId)
        if rows.isEmpty {
            Text("Pas encore de mesure. Charge ce modèle manuellement puis lance.")
                .foregroundStyle(AppTheme.mutedForeground)
        } else {
            ForEach(rows) { r in
                resultRow(r)
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ r: LocalModelComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r.testTitle).font(.headline)
            if r.skipped {
                Text("Ignoré — \(r.skipReason ?? "")")
                    .foregroundStyle(AppTheme.mutedForeground)
            } else {
                Text(r.success ? "OK" : (r.errorMessage ?? "Échec"))
                    .foregroundStyle(r.success ? AppTheme.accent : AppTheme.danger)
                Text("Réflexion : \(r.thinkingEnabled ? "oui" : "non")")
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.mutedForeground)
                if let load = r.loadDurationMs {
                    Text(String(format: "Chargement %.0f ms", load))
                        .font(CNFont.caption)
                }
                if let ttft = r.timeToFirstTokenMs {
                    Text(String(format: "TTFT %.0f ms", ttft))
                        .font(CNFont.caption)
                }
                if let tps = r.tokensPerSecond {
                    Text(String(format: "%.1f tok/s · %d tokens", tps, r.generatedTokens))
                        .font(CNFont.caption)
                }
                if let total = r.totalMs {
                    Text(String(format: "Durée %.0f ms", total))
                        .font(CNFont.caption)
                }
                if let mem = r.residentMemoryBytes {
                    Text(String(format: "RAM ≈ %.0f Mo", Double(mem) / 1_048_576.0))
                        .font(CNFont.caption)
                }
            }
            if !r.outputPreview.isEmpty {
                Text(r.outputPreview)
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.mutedForeground)
            }
        }
    }

    private func runSuite() async {
        running = true
        defer { running = false }
        current = await LocalModelComparisonRunner.runSuite(thinkingEnabled: thinkingEnabled)
    }
}
