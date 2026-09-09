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
    @Binding var presentedSheet: LocalAISettingsSheetItem?
    @AppStorage("localAI.settings.installedModelsExpanded") private var installedModelsExpanded = false
    @ObservedObject private var models = LocalModelManager.shared
    @ObservedObject private var execution = ExecutionModeStore.shared

    @State private var busyAction = false
    @State private var pendingLoadWarning: LocalModelDescriptor?
    @State private var confirmLoadExperimental = false
    @State private var pendingDelete: LocalModelDescriptor?

    private var mutationsDisabled: Bool {
        !LocalAISettingsActionGate.allowsNewMutationTask(
            busyAction: busyAction,
            exclusiveOperation: models.exclusiveOperation,
            state: models.state
        )
    }

    private var installedModels: [LocalModelDescriptor] {
        LocalModelDescriptor.userFacingCatalog.filter { models.isFullyInstalled($0) }
    }

    private var availableModels: [LocalModelDescriptor] {
        LocalModelDescriptor.userFacingCatalog.filter { !models.isFullyInstalled($0) }
    }

    var body: some View {
        // Les `.sheet` IA locale sont hissées sur `SettingsView` (une seule
        // présentation). Les empiler ici sur le `Section` fermait Tester tout de suite.
        iaLocaleSection
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
            .alert(
                "Supprimer le modèle ?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { model in
                Button("Annuler", role: .cancel) { pendingDelete = nil }
                Button("Supprimer", role: .destructive) {
                    requestDelete(model)
                    pendingDelete = nil
                }
            } message: { model in
                Text("« \(model.displayName) » sera retiré de l’iPhone. Tu pourras le télécharger à nouveau.")
            }
        installedSection
        availableSection
    }

    // MARK: - Sections

    private var iaLocaleSection: some View {
        Section {
            executionPicker
            currentModelCard
        } header: {
            Text("IA locale")
        } footer: {
            Text("Un seul modèle local est chargé à la fois.")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var installedSection: some View {
        Section {
            installedHeaderRow
            if installedModelsExpanded {
                if installedModels.isEmpty {
                    Text("Aucun modèle installé pour le moment.")
                        .font(CNFont.callout)
                        .foregroundStyle(AppTheme.mutedForeground)
                } else {
                    ForEach(installedModels) { model in
                        installedModelRow(model)
                    }
                }
            }
        }
        .listRowBackground(AppTheme.surface)
    }

    private var availableSection: some View {
        Section {
            if availableModels.isEmpty {
                Text("Tous les modèles disponibles sont installés.")
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.mutedForeground)
            } else {
                ForEach(availableModels) { model in
                    availableModelRow(model)
                }
            }
        } header: {
            Text("Modèles disponibles")
        } footer: {
            Text("Une réinstallation de l’app peut supprimer les fichiers téléchargés.")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var installedHeaderRow: some View {
        Button {
            withAnimation(.easeInOut(duration: AppTheme.motionStandard)) {
                installedModelsExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text("Mes modèles")
                    .font(CNFont.body.weight(.semibold))
                    .foregroundStyle(AppTheme.foreground)
                Text("·")
                    .foregroundStyle(AppTheme.mutedForeground)
                Text(installedCountLabel)
                    .foregroundStyle(AppTheme.mutedForeground)
                Spacer(minLength: 8)
                Image(systemName: installedModelsExpanded ? "chevron.up" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.mutedForeground)
                    .frame(width: 22, height: 22)
            }
            .frame(minHeight: AppTheme.touchMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11yID.Settings.localAIInstalledToggle)
        .accessibilityLabel("Mes modèles, \(installedCountLabel)")
        .accessibilityValue(installedModelsExpanded ? "Ouvert" : "Fermé")
        .accessibilityHint(installedModelsExpanded ? "Replier la liste" : "Afficher les modèles installés")
        .accessibilityAddTraits(.isButton)
    }

    private var installedCountLabel: String {
        let n = installedModels.count
        return n <= 1 ? "\(n) installé" : "\(n) installés"
    }

    // MARK: - Exécution

    private var preferenceBinding: Binding<ExecutionModePreference> {
        Binding(
            get: { execution.preference },
            set: { execution.setPreference($0) }
        )
    }

    private var executionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
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

    // MARK: - Modèle actuel

    private var currentModelCard: some View {
        let active = models.activeDescriptor
        let loadingName = active.displayName
        return VStack(alignment: .leading, spacing: AppTheme.space8) {
            Text("Modèle actuel")
                .font(CNFont.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.mutedForeground)

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: models.isReady ? "checkmark" : "cpu")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(models.isReady ? AppTheme.accent : AppTheme.mutedForeground)
                    .frame(width: 16, height: AppTheme.touchMin)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(active.displayName)
                            .font(CNFont.body.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        if active.recommended, models.isReady {
                            LocalAIRecommendedBadge()
                        }
                    }
                }
                Spacer(minLength: 4)
                currentStatusMark
                modelActionsMenu(active, isActive: models.isReady)
            }

            if !isTransitioningRuntime {
                Text(active.userFacingBlurb)
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                Text(currentMetaLine(active))
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.mutedForeground)
            }

            if case .loading = models.state {
                runtimeProgress("Chargement de \(loadingName)…")
            } else if case .unloading = models.state {
                runtimeProgress("Déchargement…")
            }

            if let err = visibleError(for: active.id) {
                compactErrorBlock(err, retry: { requestLoad(active) })
            }

            if models.isReady {
                Button("Tester") {
                    LocalModelTestUILog.event("present requested", extra: "caller=currentModelTester")
                    presentedSheet = .inferenceTest
                }
                    .font(CNFont.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(minHeight: AppTheme.touchMin, alignment: .leading)
                    .contentShape(Rectangle())
                    .disabled(mutationsDisabled)
                    .accessibilityHint("Génère une courte réponse de contrôle")
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier(A11yID.Settings.localAICurrent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(currentAccessibilityLabel)
    }

    @ViewBuilder
    private var currentStatusMark: some View {
        if case .failed = models.state {
            LocalAIStatusMark(kind: .error)
        } else if case .loading = models.state {
            LocalAIStatusMark(kind: .loading)
        } else if case .unloading = models.state {
            LocalAIStatusMark(kind: .loading)
        } else if models.isReady {
            LocalAIStatusMark(kind: .active)
        } else if case .notInstalled = models.state {
            Text("Non chargé")
                .font(CNFont.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.mutedForeground)
        } else {
            LocalAIStatusMark(kind: .installed)
        }
    }

    private var isTransitioningRuntime: Bool {
        switch models.state {
        case .loading, .unloading:
            return true
        default:
            return false
        }
    }

    private var currentAccessibilityLabel: String {
        let name = models.activeDescriptor.displayName
        if models.isReady { return "Modèle actuel \(name), actif" }
        if case .loading = models.state { return "Chargement de \(name)" }
        return "Modèle actuel \(name)"
    }

    private func currentMetaLine(_ model: LocalModelDescriptor) -> String {
        var parts = [model.familyDisplayName, model.quant, model.userFacingTextSizeLabel]
        if let vision = visionCapabilityLabel(model) {
            parts.append(vision)
        }
        return parts.joined(separator: " · ")
    }

    private func visionCapabilityLabel(_ model: LocalModelDescriptor) -> String? {
        guard model.mmproj != nil else { return nil }
        if models.isInstallingVision(model) { return "Vision…" }
        if models.isVisionProjectorInstalled(model) { return "Vision ✓" }
        return "Vision"
    }

    private func runtimeProgress(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(AppTheme.accent)
            Text(title)
                .font(CNFont.caption.weight(.semibold))
                .foregroundStyle(AppTheme.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    // MARK: - Lignes installées

    private func installedModelRow(_ model: LocalModelDescriptor) -> some View {
        let isActive = models.activeModelId == model.id && models.isReady
        let err = visibleError(for: model.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.displayName)
                            .font(CNFont.callout.weight(.semibold))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        if isActive {
                            LocalAIStatusMark(kind: .active)
                        }
                    }
                    Text(model.userFacingBlurb)
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.mutedForeground)
                        .lineLimit(2)
                    Text(installedMetaLine(model))
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                }
                Spacer(minLength: 4)
                if !isActive {
                    LocalAICompactChip(
                        title: "Utiliser",
                        enabled: !mutationsDisabled
                            && LocalInferenceEngine.isLlamaRuntimeAvailable
                            && models.canLoad(model)
                    ) {
                        requestLoad(model)
                    }
                    .accessibilityLabel("Utiliser \(model.displayName)")
                }
                modelActionsMenu(model, isActive: isActive)
            }
            if models.isInstallingVision(model) {
                ProgressView(value: models.visionProjectorProgress)
                    .tint(AppTheme.accent)
            }
            if let err, model.id != models.activeModelId {
                compactErrorBlock(err, retry: { requestLoad(model) })
            }
        }
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(installedAccessibilityLabel(model, isActive: isActive))
    }

    private func installedMetaLine(_ model: LocalModelDescriptor) -> String {
        var parts = [
            model.familyDisplayName,
            model.parameterCountLabel,
            model.quant,
            model.userFacingTextSizeLabel,
        ]
        if let vision = visionCapabilityLabel(model) {
            parts.append(vision)
        } else {
            parts.append("Vision non")
        }
        return parts.joined(separator: " · ")
    }

    private func installedAccessibilityLabel(_ model: LocalModelDescriptor, isActive: Bool) -> String {
        var parts = [model.displayName]
        parts.append(isActive ? "actif" : "installé")
        if let vision = visionCapabilityLabel(model) {
            parts.append(vision)
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func modelActionsMenu(_ model: LocalModelDescriptor, isActive: Bool) -> some View {
        Menu {
            if isActive {
                Button("Tester") {
                    LocalModelTestUILog.event("present requested", extra: "caller=modelMenuTester")
                    presentedSheet = .inferenceTest
                }
            } else {
                Button("Utiliser") { requestLoad(model) }
                    .disabled(mutationsDisabled || !LocalInferenceEngine.isLlamaRuntimeAvailable || !models.canLoad(model))
            }
            if model.mmproj != nil {
                Button("Gérer la vision") { presentedSheet = .visionManage(model) }
            }
            Button("Détails") { presentedSheet = .modelDetails(model) }
            Divider()
            Button("Supprimer", role: .destructive) {
                pendingDelete = model
            }
            .disabled(mutationsDisabled || models.isInstallingText(model))
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.mutedForeground)
                .frame(width: AppTheme.touchMin, height: AppTheme.touchMin)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .disabled(models.isInstallingText(model))
        .accessibilityLabel("Actions pour \(model.displayName)")
        .accessibilityHint("Utiliser, vision, détails ou supprimer")
    }

    // MARK: - Lignes disponibles

    private func availableModelRow(_ model: LocalModelDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(CNFont.callout.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Text(model.familyDisplayName)
                        .font(CNFont.caption2.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedForeground)
                    Text(model.userFacingBlurb)
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.mutedForeground)
                    if !models.isInstallingText(model) {
                        availableSizeBlock(model)
                    }
                    availableStatusRow(model)
                }
                Spacer(minLength: 4)
                availableActionChip(model)
            }

            if models.isInstallingText(model) {
                downloadProgressBlock(model)
            } else if models.isInstallingVision(model) {
                ProgressView(value: models.visionProjectorProgress)
                    .tint(AppTheme.accent)
                Text("Vision \(Int((models.visionProjectorProgress * 100).rounded())) %")
                    .font(CNFont.caption2)
                    .foregroundStyle(AppTheme.mutedForeground)
            } else if let err = visibleError(for: model.id) {
                compactErrorBlock(err, retry: { requestInstall(model) })
            }
        }
        .padding(.vertical, 2)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(availableAccessibilityLabel(model))
    }

    @ViewBuilder
    private func availableActionChip(_ model: LocalModelDescriptor) -> some View {
        if !model.isRuntimeCompatible {
            LocalAICompactChip(
                title: "Détails",
                kind: .outline,
                enabled: true
            ) {
                presentedSheet = .modelDetails(model)
            }
            .accessibilityLabel("Détails de \(model.displayName)")
        } else if models.isInstallingText(model) || models.isInstallingVision(model) {
            EmptyView()
        } else if visibleError(for: model.id) != nil {
            EmptyView()
        } else if models.isInstalled(model), model.requiresCompanionVisionToLoad, !models.isVisionProjectorInstalled(model) {
            LocalAICompactChip(
                title: "Vision",
                enabled: !mutationsDisabled && !models.visionProjectorBusy
            ) {
                presentedSheet = .visionManage(model)
            }
            .accessibilityLabel("Installer la vision de \(model.displayName)")
        } else if model.isDownloadable {
            LocalAICompactChip(
                title: "Télécharger",
                enabled: !mutationsDisabled && !models.textInstallBusy
            ) {
                requestInstall(model)
            }
            .accessibilityLabel("Télécharger \(model.displayName)")
        }
    }

    @ViewBuilder
    private func availableStatusRow(_ model: LocalModelDescriptor) -> some View {
        if !model.isRuntimeCompatible {
            LocalAIStatusMark(kind: .incompatible)
        } else if models.isInstallingText(model) || models.isInstallingVision(model) {
            LocalAIStatusMark(kind: .downloading)
        } else if models.isInstalled(model), model.requiresCompanionVisionToLoad {
            Text("Vision requise")
                .font(CNFont.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.mutedForeground)
        } else {
            LocalAIStatusMark(kind: .available)
        }
    }

    private func availableAccessibilityLabel(_ model: LocalModelDescriptor) -> String {
        if let reason = model.runtimeIncompatibilityReason {
            return "\(model.displayName), non compatible, \(reason)"
        }
        return "\(model.displayName), \(model.familyDisplayName), \(model.userFacingTextSizeLabel)"
    }

    @ViewBuilder
    private func availableSizeBlock(_ model: LocalModelDescriptor) -> some View {
        let showFootprint = model.mmproj != nil || model.expectedBytes >= 1_500_000_000
        VStack(alignment: .leading, spacing: 1) {
            if showFootprint, let vision = model.userFacingVisionSizeLabel {
                Text("~\(model.userFacingTextSizeLabel) · \(model.quant)")
                Text("+ \(vision) vision")
                Text("≈ \(model.userFacingPackSizeLabel) au total")
            } else if model.expectedBytes > 0 {
                Text("~\(model.userFacingTextSizeLabel) · \(model.quant)")
            }
            if let reason = model.runtimeIncompatibilityReason {
                Text(reason)
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showFootprint, let free = LocalDeviceStorageInfo.availableLabel() {
                let needed = model.expectedBytes
                let freeBytes = LocalDeviceStorageInfo.availableImportantBytes()
                Text(free)
                    .foregroundStyle(
                        (freeBytes.map { $0 < needed } ?? false) ? AppTheme.danger : AppTheme.mutedForeground
                    )
            }
        }
        .font(CNFont.caption2)
        .foregroundStyle(AppTheme.mutedForeground)
    }

    private func downloadProgressBlock(_ model: LocalModelDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LocalAIStatusMark(kind: .downloading)
            ProgressView(value: models.textInstallProgress)
                .tint(AppTheme.accent)
            HStack {
                Text(downloadBytesCaption(model: model, fraction: models.textInstallProgress))
                    .font(CNFont.caption2)
                    .foregroundStyle(AppTheme.mutedForeground)
                Spacer()
                Text("\(Int((models.textInstallProgress * 100).rounded())) %")
                    .font(CNFont.caption2.weight(.semibold))
                    .foregroundStyle(AppTheme.foreground)
            }
            Button("Annuler") {
                models.cancelDownload()
            }
            .font(CNFont.caption.weight(.semibold))
            .foregroundStyle(AppTheme.danger)
            .frame(minHeight: AppTheme.touchMin, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Téléchargement de \(model.displayName), \(Int((models.textInstallProgress * 100).rounded())) pour cent")
    }

    private func downloadBytesCaption(model: LocalModelDescriptor, fraction: Double) -> String {
        let clamped = min(1, max(0, fraction))
        let done = Int64((Double(model.expectedBytes) * clamped).rounded())
        return "\(LocalModelByteLabel.decimal(done)) / \(model.userFacingTextSizeLabel)"
    }

    private func compactErrorBlock(_ raw: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.danger)
                    .font(.caption)
                    .accessibilityHidden(true)
                Text(humanLocalAIError(raw))
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                LocalAICompactChip(
                    title: "Réessayer",
                    kind: .outline,
                    enabled: !mutationsDisabled
                ) {
                    retry()
                }
                Button("Détails de l’erreur") {
                    presentedSheet = .technicalError(models.lastError ?? "")
                }
                .font(CNFont.caption.weight(.semibold))
                .foregroundStyle(AppTheme.mutedForeground)
                .frame(minHeight: AppTheme.touchMin)
                .contentShape(Rectangle())
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Erreur : \(humanLocalAIError(raw))")
    }

    // MARK: - Erreurs

    private func visibleError(for modelId: String) -> String? {
        guard let err = models.lastError, !err.isEmpty, !models.textInstallBusy else { return nil }
        if case .failed = models.state, modelId == models.activeModelId {
            return err
        }
        return errorTargetModelId() == modelId ? err : nil
    }

    private func errorTargetModelId() -> String? {
        guard let err = models.lastError, !err.isEmpty else { return nil }
        for model in LocalModelDescriptor.userFacingCatalog {
            if err.contains(model.displayName) || err.contains(model.id) {
                return model.id
            }
        }
        if models.isReady, availableModels.count == 1, looksLikeDownloadError(err) {
            return availableModels[0].id
        }
        return models.activeModelId
    }

    private func looksLikeDownloadError(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains("télécharg")
            || lower.contains("download")
            || lower.contains("réseau")
            || lower.contains("network")
            || lower.contains("http")
            || lower.contains("espace")
            || lower.contains("disk")
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
            return "Mémoire insuffisante pour charger ce modèle."
        }
        if raw.count > 140 {
            return "Impossible de charger ce modèle."
        }
        return raw
    }

    // MARK: - Actions (logique inchangée)

    private func requestLoad(_ model: LocalModelDescriptor) {
        guard models.canLoad(model) else { return }
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

    private func requestInstall(_ model: LocalModelDescriptor) {
        guard beginUIAction() else { return }
        Task {
            defer { busyAction = false }
            await models.install(model: model)
        }
    }

    private func requestDelete(_ model: LocalModelDescriptor) {
        guard beginUIAction() else { return }
        Task {
            defer { busyAction = false }
            await models.deleteModel(model)
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
}

// MARK: - Comparison sheet (debug)

struct LocalModelComparisonSheet: View {
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
