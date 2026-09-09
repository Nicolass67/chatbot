import SwiftUI

/// Session de la feuille Tester : un run ID par type de test.
/// Un callback async d’un ancien run ne peut pas écrire sur le run suivant.
@MainActor
final class LocalModelTestSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case running
        case success
        case error
    }

    @Published var textPhase: Phase = .idle
    @Published var visionPhase: Phase = .idle
    @Published var abPhase: Phase = .idle
    @Published var textOutput = ""
    @Published var textError: String?
    @Published var textMetrics: LocalModelBenchmarkResult?
    @Published var visionOutput = ""
    @Published var visionError: String?
    @Published var visionDurationMs: Double?
    @Published var visionSuite: [LocalVisionProbeResult] = []
    @Published var visionSuiteCurrent: String?
    @Published var abReport: LocalThreadABReport?
    @Published var abError: String?
    @Published var gdn = LlamaGdnProbeObservation.unknown
    @Published private(set) var dismissRequested = false

    private var textRun = UUID()
    private var visionRun = UUID()
    private var abRun = UUID()
    private var invalidated = false

    var isBusy: Bool {
        textPhase == .running || visionPhase == .running || abPhase == .running
    }

    var textStatusTitle: String {
        switch textPhase {
        case .idle: return "Prêt"
        case .running: return "Génération en cours…"
        case .success: return "Succès"
        case .error: return "Échec du test"
        }
    }

    func startText() -> UUID {
        let id = UUID()
        textRun = id
        textPhase = .running
        textError = nil
        textOutput = ""
        textMetrics = nil
        LocalModelTestUILog.event("test started", extra: "kind=text run=\(id.uuidString)")
        LocalModelTestUILog.event("TEST_STARTED", extra: "kind=text")
        return id
    }

    func applyText(run: UUID, result: LocalModelBenchmarkResult) {
        guard isCurrent(run, vs: textRun, kind: "text") else { return }
        textMetrics = result
        textOutput = ChatMLPromptBuilder.stripControlTokens(result.outputPreview)
        if result.success {
            textPhase = .success
            textError = nil
            LocalModelTestUILog.event("generation finished", extra: "kind=text success=true tokens=\(result.generatedTokens)")
            LocalModelTestUILog.event("TEST_GENERATION_FINISHED", extra: "kind=text")
        } else {
            textPhase = .error
            textError = result.errorMessage ?? "Impossible de générer une réponse."
            LocalModelTestUILog.event("generation failed", extra: "kind=text error=\(textError ?? "")")
            LocalModelTestUILog.event("TEST_GENERATION_FAILED", extra: "kind=text")
        }
    }

    func failText(run: UUID, message: String) {
        guard isCurrent(run, vs: textRun, kind: "text") else { return }
        textPhase = .error
        textError = message
        LocalModelTestUILog.event("generation failed", extra: "kind=text error=\(message)")
        LocalModelTestUILog.event("TEST_GENERATION_FAILED", extra: "kind=text")
    }

    func startVision() -> UUID {
        let id = UUID()
        visionRun = id
        visionPhase = .running
        visionError = nil
        visionOutput = ""
        visionDurationMs = nil
        visionSuite = []
        visionSuiteCurrent = nil
        LocalModelTestUILog.event("test started", extra: "kind=vision run=\(id.uuidString)")
        LocalModelTestUILog.event("TEST_STARTED", extra: "kind=vision")
        return id
    }

    func applyVision(run: UUID, output: String, durationMs: Double) {
        guard isCurrent(run, vs: visionRun, kind: "vision") else { return }
        visionOutput = output
        visionDurationMs = durationMs
        visionPhase = .success
        visionError = nil
        LocalModelTestUILog.event("generation finished", extra: "kind=vision success=true durationMs=\(Int(durationMs))")
        LocalModelTestUILog.event("TEST_GENERATION_FINISHED", extra: "kind=vision")
    }

    func failVision(run: UUID, message: String) {
        guard isCurrent(run, vs: visionRun, kind: "vision") else { return }
        visionPhase = .error
        visionError = message
        LocalModelTestUILog.event("generation failed", extra: "kind=vision error=\(message)")
        LocalModelTestUILog.event("TEST_GENERATION_FAILED", extra: "kind=vision")
    }

    func applyVisionProbe(_ result: LocalVisionProbeResult) {
        visionSuiteCurrent = result.title
        visionSuite.append(result)
        visionOutput = result.outputPreview
        visionDurationMs = result.totalMs
        if result.success {
            visionError = nil
        }
    }

    func finishVisionSuite() {
        let failed = visionSuite.filter { !$0.success }
        if visionSuite.isEmpty {
            visionPhase = .error
            visionError = visionError ?? "Aucun test vision n’a été exécuté."
        } else if failed.count == visionSuite.count {
            visionPhase = .error
            visionError = failed.first?.errorMessage ?? "Tous les tests vision ont échoué."
        } else {
            visionPhase = .success
            if !failed.isEmpty {
                visionError = "\(failed.count) échec\(failed.count > 1 ? "s" : "") sur \(visionSuite.count)"
            }
        }
        visionSuiteCurrent = nil
        LocalModelTestUILog.event("TEST_GENERATION_FINISHED", extra: "kind=vision suite=\(visionSuite.count)")
    }

    func startAB() -> UUID {
        let id = UUID()
        abRun = id
        abPhase = .running
        abError = nil
        LocalModelTestUILog.event("test started", extra: "kind=thread-ab run=\(id.uuidString)")
        LocalModelTestUILog.event("TEST_STARTED", extra: "kind=thread-ab")
        return id
    }

    func applyAB(run: UUID, report: LocalThreadABReport) {
        guard isCurrent(run, vs: abRun, kind: "thread-ab") else { return }
        abReport = report
        let measured = report.runs.filter { !$0.warmup }
        if measured.isEmpty || measured.allSatisfy({ !$0.success }) {
            abPhase = .error
            abError = "Aucune mesure — le modèle n’était pas chargé, ou la génération a échoué."
            LocalModelTestUILog.event("generation failed", extra: "kind=thread-ab")
            LocalModelTestUILog.event("TEST_GENERATION_FAILED", extra: "kind=thread-ab")
        } else {
            abPhase = .success
            abError = nil
            LocalModelTestUILog.event("generation finished", extra: "kind=thread-ab success=true")
            LocalModelTestUILog.event("TEST_GENERATION_FINISHED", extra: "kind=thread-ab")
        }
    }

    func failAB(run: UUID, message: String) {
        guard isCurrent(run, vs: abRun, kind: "thread-ab") else { return }
        abPhase = .error
        abError = message
        LocalModelTestUILog.event("generation failed", extra: "kind=thread-ab error=\(message)")
        LocalModelTestUILog.event("TEST_GENERATION_FAILED", extra: "kind=thread-ab")
    }

    func noteDismissRequested() {
        dismissRequested = true
    }

    func invalidate(reason: String) {
        guard !invalidated else { return }
        invalidated = true
        textRun = UUID()
        visionRun = UUID()
        abRun = UUID()
        LocalModelTestUILog.event("task cancelled", extra: "reason=\(reason)")
        LocalModelTestUILog.event("TEST_TASK_CANCELLED", extra: "reason=\(reason)")
    }

    private func isCurrent(_ run: UUID, vs current: UUID, kind: String) -> Bool {
        if invalidated || run != current {
            LocalModelTestUILog.event(
                "task cancelled",
                extra: "kind=\(kind) stale run=\(run.uuidString) current=\(current.uuidString) invalidated=\(invalidated)"
            )
            LocalModelTestUILog.event("TEST_TASK_CANCELLED", extra: "kind=\(kind) stale=true")
            return false
        }
        return true
    }
}

struct LocalModelTestSheet: View {
    static let textProbePrompt = "Réponds uniquement par : Test OK."
    static let testerModelIds = [
        "qwen35-2b-q4_k_m",
        "lfm25-vl-3b-q4_k_m",
        "north-micro-vision-instruct",
        "minicpm-v46-thinking-q4_k_m",
    ]

    @ObservedObject private var models = LocalModelManager.shared
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = LocalModelTestSession()
    @State private var selectedModelId = LocalModelManager.shared.activeModelId
    @State private var switchError: String?
    @State private var switchingModel = false
    @State private var benchResults: [LocalModelBenchmarkResult] = []
    @State private var benchPhase: LocalModelTestSession.Phase = .idle

    private var testerModels: [LocalModelDescriptor] {
        var ids = Self.testerModelIds
        if !ids.contains(models.activeModelId) {
            ids.insert(models.activeModelId, at: 0)
        }
        return ids.compactMap { LocalModelDescriptor.descriptor(id: $0) }
    }

    var body: some View {
        NavigationStack {
            List {
                modelPickerSection
                textTestSection
                runtimeDiagnosticSection
                visionSection
                benchmarkSection
                threadABSection
            }
            .navigationTitle("Test local")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .accessibilityIdentifier(A11yID.Settings.localAITestSheet)
        }
        .onAppear {
            LocalModelTestUILog.event("sheet presented")
            LocalModelTestUILog.event("TEST_SHEET_PRESENTED")
            Task { await refreshGdn() }
        }
        .onDisappear {
            let reason: String
            if session.dismissRequested {
                reason = "requested"
            } else {
                reason = "unsolicited SwiftUI (pas de dismiss() métier — presentateur recréé, sheet empilée, ou geste système)"
            }
            LocalModelTestUILog.event("sheet dismissed", extra: "reason=\(reason) busy=\(session.isBusy)")
            LocalModelTestUILog.event("TEST_SHEET_DISMISSED", extra: "reason=\(reason)")
            if session.isBusy {
                Task { await LocalInferenceEngine.shared.cancel() }
            }
            session.invalidate(reason: "sheet-disappear")
        }
        .onChange(of: models.state) { _, newState in
            LocalModelTestUILog.event(
                "model state changed",
                extra: "state=\(String(describing: newState)) (aucun dismiss)"
            )
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Fermer") {
                LocalModelTestUILog.dismissRequested(caller: "closeButton", running: session.isBusy)
                session.noteDismissRequested()
                Task { await LocalInferenceEngine.shared.cancel() }
                dismiss()
            }
            .accessibilityIdentifier(A11yID.Settings.localAITestClose)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Vision") {
                Task { await runVisionSuite() }
            }
            .disabled(session.isBusy || switchingModel || benchPhase == .running)
            Button("A/B 2/4") {
                Task { await runThreadAB() }
            }
            .disabled(session.isBusy || switchingModel || benchPhase == .running)
            Button("Lancer") {
                Task { await runTextTest() }
            }
            .disabled(session.isBusy || switchingModel || benchPhase == .running)
            .accessibilityIdentifier(A11yID.Settings.localAITestLaunch)
        }
    }

    private var modelPickerSection: some View {
        Section {
            Picker("Modèle", selection: $selectedModelId) {
                ForEach(testerModels) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            .disabled(session.isBusy || switchingModel || benchPhase == .running)
            .onChange(of: selectedModelId) { _, newId in
                Task { await applyTesterModelSelection(newId) }
            }
            if switchingModel {
                ProgressView("Changement de modèle…")
            }
            if let switchError {
                Text(switchError)
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.danger)
            }
            Text("Un seul modèle chargé à la fois. Changer de modèle décharge l’actuel.")
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.mutedForeground)
        } header: {
            Text("Modèle")
        }
    }

    private var textTestSection: some View {
        Section {
            Text(models.activeDescriptor.displayName)
                .font(CNFont.body.weight(.semibold))
            statusRow(title: "Statut", phase: session.textPhase, label: session.textStatusTitle)
            if session.textPhase == .running {
                ProgressView("Génération en cours…")
            }
            if session.textPhase == .success, let metrics = session.textMetrics {
                LabeledContent("TTFT", value: LocalModelTestFormat.seconds(fromMs: metrics.timeToFirstTokenMs))
                LabeledContent("Vitesse", value: LocalModelTestFormat.tokensPerSecond(metrics.tokensPerSecond))
                LabeledContent("Tokens", value: "\(metrics.generatedTokens)")
                LabeledContent("Durée", value: LocalModelTestFormat.seconds(fromMs: metrics.totalMs))
            }
            if session.textPhase == .error {
                Text(session.textError ?? "Impossible de générer une réponse.")
                    .foregroundStyle(AppTheme.danger)
                    .font(CNFont.callout)
                Button("Réessayer") {
                    Task { await runTextTest() }
                }
                .disabled(session.isBusy)
            }
            if !session.textOutput.isEmpty {
                Text(session.textOutput)
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.mutedForeground)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Test texte")
        } footer: {
            Text("Le bouton Lancer envoie « \(Self.textProbePrompt) ». Vision et A/B 2/4 restent séparés.")
        }
    }

    private var runtimeDiagnosticSection: some View {
        Section {
            LabeledContent("GDN", value: session.gdn.userFacingFusedLabel)
            Text(session.gdn.userFacingFusedCaption)
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.mutedForeground)
            DisclosureGroup("Détails techniques") {
                Text(session.gdn.explicitReport)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                if session.gdn.rawLines.isEmpty {
                    Text("Les logs llama.cpp n’ont pas mentionné GDN. Le verdict ci-dessus vient du graphe d’exécution, pas de ces logs.")
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.mutedForeground)
                }
            }
        } header: {
            Text("Diagnostic runtime")
        } footer: {
            Text("Le diagnostic GDN observe le graphe d’exécution. « Indéterminable » signifie que le chemin n’a pas pu être lu, pas que GDN est absent.")
        }
    }

    private var visionSection: some View {
        Section {
            LabeledContent("Vision", value: visionStatusLabel)
            if session.visionPhase == .running {
                ProgressView(session.visionSuiteCurrent.map { "Vision : \($0)…" } ?? "Test vision…")
            }
            if let duration = session.visionDurationMs, session.visionPhase == .success, session.visionSuite.isEmpty {
                LabeledContent("Durée", value: LocalModelTestFormat.seconds(fromMs: duration))
            }
            if session.visionPhase == .error {
                Text(session.visionError ?? "Échec du test vision.")
                    .foregroundStyle(AppTheme.danger)
                    .font(CNFont.callout)
            }
            if !session.visionSuite.isEmpty {
                ForEach(session.visionSuite) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(CNFont.callout.weight(.semibold))
                        Text(visionProbeMetricsLine(row))
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.mutedForeground)
                        if let err = row.errorMessage, !row.success {
                            Text(err)
                                .font(CNFont.caption)
                                .foregroundStyle(AppTheme.danger)
                        } else if !row.outputPreview.isEmpty {
                            Text(row.outputPreview)
                                .font(CNFont.caption)
                                .foregroundStyle(AppTheme.mutedForeground)
                                .lineLimit(3)
                        }
                    }
                }
            } else if !session.visionOutput.isEmpty {
                Text(session.visionOutput)
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.mutedForeground)
                    .textSelection(.enabled)
            }
            Button("Tester la vision") {
                Task { await runVisionSuite() }
            }
            .disabled(session.isBusy || switchingModel || benchPhase == .running)
        } header: {
            Text("Test Vision")
        } footer: {
            Text("Les 7 cas (image, capture, document, OCR, tableau, question, raisonnement) sont identiques pour chaque modèle. Aucun benchmark automatique.")
        }
    }

    private var benchmarkSection: some View {
        Section {
            if benchPhase == .running {
                ProgressView("Benchmark…")
            }
            ForEach(benchResults) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.promptLabel)
                        .font(CNFont.callout.weight(.semibold))
                    Text(benchmarkMetricsLine(row))
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.mutedForeground)
                    if !row.success {
                        Text(row.errorMessage ?? "Échec")
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.danger)
                    }
                }
            }
            Button("Benchmark") {
                Task { await runBenchmark() }
            }
            .disabled(session.isBusy || switchingModel || benchPhase == .running)
        } header: {
            Text("Benchmark")
        } footer: {
            Text("Manuel uniquement. Mesure TTFT, tok/s, durée et RAM sur le modèle déjà chargé.")
        }
    }

    private func visionProbeMetricsLine(_ row: LocalVisionProbeResult) -> String {
        let ttft = LocalModelTestFormat.seconds(fromMs: row.timeToFirstTokenMs)
        let tps = LocalModelTestFormat.tokensPerSecond(row.tokensPerSecond)
        let dur = LocalModelTestFormat.seconds(fromMs: row.totalMs)
        let ram: String
        if let bytes = row.residentMemoryBytes {
            ram = String(format: "%.0f Mo", Double(bytes) / 1_048_576.0)
        } else {
            ram = "—"
        }
        let status = row.success ? "OK" : "échec"
        return "\(status) · TTFT \(ttft) · \(tps) · \(dur) · RAM \(ram) · ctx \(row.promptTokens)/\(row.nCtx ?? 0)"
    }

    private func benchmarkMetricsLine(_ row: LocalModelBenchmarkResult) -> String {
        let ttft = LocalModelTestFormat.seconds(fromMs: row.timeToFirstTokenMs)
        let tps = LocalModelTestFormat.tokensPerSecond(row.tokensPerSecond)
        let dur = LocalModelTestFormat.seconds(fromMs: row.totalMs)
        let status = row.success ? "OK" : "échec"
        return "\(status) · TTFT \(ttft) · \(tps) · \(dur)"
    }

    private var threadABSection: some View {
        Section {
            if session.abPhase == .running {
                ProgressView("A/B threads 2 vs 4… (plusieurs minutes)")
            }
            if session.abPhase == .error {
                Text(session.abError ?? "Échec du benchmark.")
                    .foregroundStyle(AppTheme.danger)
                    .font(CNFont.callout)
            }
            if let report = session.abReport, session.abPhase != .idle {
                Text(report.userFacingSummary)
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.foreground)
                DisclosureGroup("Détails A/B") {
                    Text(report.explicitSummary)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            } else if session.abPhase == .idle {
                Text("A/B 2/4 compare 2 et 4 threads sur le modèle déjà chargé, puis restaure le réglage de production.")
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.mutedForeground)
            }
        } header: {
            Text("A/B 2/4")
        } footer: {
            Text("Ce benchmark ne se lance pas à l’ouverture de la feuille.")
        }
    }

    private var visionStatusLabel: String {
        let model = models.activeDescriptor
        guard model.mmproj != nil else { return "Non installée" }
        if models.isInstallingVision(model) { return "Disponible" }
        if models.isVisionProjectorInstalled(model) { return "Installée" }
        return "Disponible"
    }

    private func statusRow(title: String, phase: LocalModelTestSession.Phase, label: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor(phase))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(label)
                    .foregroundStyle(phase == .error ? AppTheme.danger : AppTheme.foreground)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(label)")
    }

    private func statusColor(_ phase: LocalModelTestSession.Phase) -> Color {
        switch phase {
        case .idle: return models.isReady ? AppTheme.accent : AppTheme.mutedForeground
        case .running: return AppTheme.mutedForeground
        case .success: return AppTheme.accent
        case .error: return AppTheme.danger
        }
    }

    private func refreshGdn() async {
        let gdn = await LocalInferenceEngine.shared.gdnSnapshot()
        session.gdn = gdn
        LocalModelTestUILog.event(
            "gdn diagnostic",
            extra: "path=\(gdn.pathKind.rawValue) label=\(gdn.userFacingFusedLabel) source=\(gdn.source)"
        )
    }

    private func runTextTest() async {
        let run = session.startText()
        LocalModelTestUILog.event("generation started", extra: "kind=text run=\(run.uuidString)")
        LocalModelTestUILog.event("TEST_GENERATION_STARTED", extra: "kind=text")
        guard await ensureModelReady(run: run, kind: "text") else { return }
        let result = await LocalModelBenchmarkRunner.runPrompt(
            label: "tester-smoke",
            prompt: Self.textProbePrompt,
            maxTokens: 32
        )
        await refreshGdn()
        session.applyText(run: run, result: result)
    }

    private func applyTesterModelSelection(_ id: String) async {
        switchError = nil
        guard let model = LocalModelDescriptor.descriptor(id: id) else { return }
        guard model.isRuntimeCompatible else {
            switchError = model.runtimeIncompatibilityReason
                ?? "Non compatible avec le runtime actuel"
            selectedModelId = models.activeModelId
            return
        }
        guard id != models.activeModelId else { return }
        guard models.canLoad(model) else {
            switchError = models.isInstalled(model)
                ? "Installe d’abord le projecteur vision de « \(model.displayName) »."
                : "« \(model.displayName) » n’est pas installé. Télécharge-le depuis Réglages."
            selectedModelId = models.activeModelId
            return
        }
        switchingModel = true
        defer { switchingModel = false }
        await models.switchToModel(model)
        if models.isReady, models.activeModelId == model.id {
            selectedModelId = model.id
            await refreshGdn()
        } else {
            switchError = models.lastError ?? "Impossible de charger « \(model.displayName) »."
            selectedModelId = models.activeModelId
        }
    }

    private func runVisionSuite() async {
        let run = session.startVision()
        LocalModelTestUILog.event("generation started", extra: "kind=vision-suite run=\(run.uuidString)")
        LocalModelTestUILog.event("TEST_GENERATION_STARTED", extra: "kind=vision")
        let model = models.activeDescriptor
        guard model.mmproj != nil else {
            session.failVision(run: run, message: "Ce modèle n’a pas de projecteur vision (mmproj).")
            return
        }
        guard models.isVisionProjectorInstalled(model) else {
            session.failVision(
                run: run,
                message: "Le projecteur vision n’est pas installé. Installe-le depuis Gérer la vision, puis relance ce test."
            )
            return
        }
        guard await ensureModelReady(run: run, kind: "vision") else { return }
        let results = await LocalVisionProbeRunner.run { probe in
            session.applyVisionProbe(probe)
        }
        _ = results
        session.finishVisionSuite()
    }

    private func runBenchmark() async {
        benchPhase = .running
        benchResults = []
        if models.isReady {
            // already loaded
        } else {
            let target = models.activeDescriptor
            guard models.canLoad(target) else {
                benchPhase = .error
                return
            }
            await models.switchToModel(target)
            guard models.isReady else {
                benchPhase = .error
                return
            }
        }
        var rows: [LocalModelBenchmarkResult] = []
        for prompt in LocalModelBenchmarkSuite.prompts.prefix(3) {
            let row = await LocalModelBenchmarkRunner.runPrompt(
                label: prompt.id,
                prompt: prompt.text,
                maxTokens: 48
            )
            rows.append(row)
        }
        benchResults = rows
        benchPhase = rows.contains(where: \.success) ? .success : .error
    }

    private func runThreadAB() async {
        let run = session.startAB()
        LocalModelTestUILog.event("generation started", extra: "kind=thread-ab run=\(run.uuidString)")
        LocalModelTestUILog.event("TEST_GENERATION_STARTED", extra: "kind=thread-ab")
        guard await ensureModelReady(run: run, kind: "thread-ab") else { return }
        let report = await LocalThreadABBenchmark.runIsolated(source: "settings-tester")
        await refreshGdn()
        session.applyAB(run: run, report: report)
    }

    private func ensureModelReady(run: UUID, kind: String) async -> Bool {
        if models.isReady { return true }
        let target = models.activeDescriptor
        guard models.canLoad(target) else {
            failKind(run: run, kind: kind, message: "Aucun modèle chargé. Charge-le depuis Réglages, puis relance.")
            return false
        }
        LocalModelTestUILog.event("loading model for test", extra: "kind=\(kind) model=\(target.id)")
        await models.switchToModel(target)
        guard models.isReady else {
            failKind(run: run, kind: kind, message: "Impossible de charger le modèle.")
            return false
        }
        return true
    }

    private func failKind(run: UUID, kind: String, message: String) {
        switch kind {
        case "vision":
            session.failVision(run: run, message: message)
        case "thread-ab":
            session.failAB(run: run, message: message)
        default:
            session.failText(run: run, message: message)
        }
    }
}
