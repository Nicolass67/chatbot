import SwiftUI

struct SmartOrganizerSheet: View {
    @EnvironmentObject private var session: AppSessionStore
    @Environment(\.dismiss) private var dismiss

    let scope: OrganizationScope
    var onFinished: (() async -> Void)?

    @State private var engine = SmartFileOrganizerEngine()
    @State private var refineText = ""
    @State private var undoing = false

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground()
                content
            }
            .navigationTitle("Réorganiser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.surface.opacity(0.94), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fermer") {
                        engine.requestCancel()
                        dismiss()
                    }
                    .accessibilityLabel("Fermer le réorganisateur")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if engine.phase == .inventorying
                        || engine.phase == .analyzing
                        || engine.phase == .proposing
                        || engine.phase == .validating
                        || engine.phase == .executing {
                        Button("Arrêter") {
                            engine.requestCancel()
                            AppHaptics.light()
                        }
                        .foregroundStyle(AppTheme.danger)
                        .accessibilityLabel("Arrêter la réorganisation")
                    }
                }
            }
            .task {
                engine.startAnalysis(scope: scope, client: client)
            }
        }
        .accessibilityIdentifier("smart_organizer_sheet")
    }

    @ViewBuilder
    private var content: some View {
        switch engine.phase {
        case .idle, .inventorying, .analyzing, .proposing, .validating:
            progressBlock
        case .readyForApproval, .editingProposal:
            proposalView
        case .executing:
            progressBlock
        case .completed, .partiallyCompleted, .rolledBack:
            completionView
        case .failed:
            failedView
        }
    }

    private var progressBlock: some View {
        VStack(spacing: AppTheme.space24) {
            ProgressView(value: engine.progressValue)
                .tint(AppTheme.filesAccent)
                .padding(.horizontal, AppTheme.space24)
            Text(engine.progressText.isEmpty ? "Préparation…" : engine.progressText)
                .font(CNFont.callout)
                .foregroundStyle(AppTheme.mutedForeground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppTheme.space24)
                .accessibilityLabel(engine.progressText)
            if engine.phase == .executing {
                Text("Aucune suppression — déplacements uniquement.")
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedView: some View {
        SoftEmptyState(
            systemImage: "exclamationmark.triangle",
            title: "Impossible de réorganiser",
            message: engine.lastError ?? "Une erreur est survenue.",
            actionTitle: "Réessayer"
        ) {
            engine.startAnalysis(scope: scope, client: client)
        }
    }

    private var completionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.space16) {
                Label {
                    Text(completionTitle)
                        .font(CNFont.title)
                } icon: {
                    Image(systemName: completionIcon)
                        .foregroundStyle(AppTheme.filesAccent)
                }
                .accessibilityLabel(completionTitle)

                if let result = engine.executionResult {
                    Text("\(result.succeededCount) réussi\(result.succeededCount > 1 ? "s" : "") · \(result.failedCount) échec\(result.failedCount > 1 ? "s" : "")")
                        .font(CNFont.callout)
                        .foregroundStyle(AppTheme.mutedForeground)
                }

                Text("Aucun fichier n’a été supprimé.")
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.muted)

                if OrganizationHistoryStore.shared.last != nil,
                   engine.phase == .completed || engine.phase == .partiallyCompleted {
                    Button {
                        Task {
                            undoing = true
                            await engine.undoLast(client: client)
                            undoing = false
                            await onFinished?()
                        }
                    } label: {
                        Label("Annuler la dernière réorganisation", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.filesAccent)
                    .disabled(undoing)
                    .accessibilityLabel("Annuler la dernière réorganisation")
                }

                Button {
                    Task {
                        await onFinished?()
                        dismiss()
                    }
                } label: {
                    Text("Terminer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.filesAccent)
                .accessibilityLabel("Terminer et fermer")
            }
            .padding(AppTheme.space24)
        }
    }

    private var completionTitle: String {
        switch engine.phase {
        case .completed: return "Réorganisation terminée"
        case .partiallyCompleted: return "Réorganisation partielle"
        case .rolledBack: return "Annulation terminée"
        default: return "Terminé"
        }
    }

    private var completionIcon: String {
        switch engine.phase {
        case .completed, .rolledBack: return "checkmark.circle.fill"
        default: return "exclamationmark.circle"
        }
    }

    private var proposalView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.space20) {
                if let plan = engine.plan {
                    summarySection(plan)
                    protectedSection(plan)
                    reviewSection(plan)
                    movesSection(plan)
                    refineSection
                    reminderBanner
                    approveButton
                }
            }
            .padding(AppTheme.space16)
        }
    }

    private func summarySection(_ plan: OrganizationPlan) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.space8) {
            Text("Résumé")
                .font(CNFont.headline)
                .foregroundStyle(AppTheme.foreground)
            Text(plan.summary)
                .font(CNFont.callout)
                .foregroundStyle(AppTheme.mutedForeground)
            HStack(spacing: AppTheme.space12) {
                countChip("\(plan.executableMoves.count)", label: "auto")
                countChip("\(plan.reviewMoves.count)", label: "revue")
                countChip("\(plan.proposedDirectories.count)", label: "dossiers")
                countChip("\(plan.moves.filter(\.excluded).count)", label: "exclus")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(plan.executableMoves.count) automatiques, \(plan.reviewMoves.count) à revoir, \(plan.proposedDirectories.count) dossiers"
            )
        }
        .padding(AppTheme.space14)
        .background(AppTheme.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
    }

    private func countChip(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(CNFont.headline)
                .foregroundStyle(AppTheme.filesAccent)
            Text(label)
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func protectedSection(_ plan: OrganizationPlan) -> some View {
        let protected = plan.protectedStructures.filter { $0.level == .protected }
        if !protected.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.space8) {
                Text("Structures protégées")
                    .font(CNFont.headline)
                ForEach(protected) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(AppTheme.filesAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(CNFont.callout)
                            Text(item.reason)
                                .font(CNFont.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                    .accessibilityLabel("Protégé : \(item.name), \(item.reason)")
                }
            }
        }
    }

    @ViewBuilder
    private func reviewSection(_ plan: OrganizationPlan) -> some View {
        let reviews = plan.reviewMoves
        if !reviews.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.space8) {
                Text("À revoir")
                    .font(CNFont.headline)
                Text("Ces fichiers ne seront pas déplacés automatiquement. Tu peux les exclure ou les affiner.")
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.muted)
                ForEach(reviews) { move in
                    moveRow(move, badge: "Revue")
                }
            }
        }
    }

    private func movesSection(_ plan: OrganizationPlan) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.space8) {
            Text("Déplacements proposés")
                .font(CNFont.headline)
            if plan.moves.isEmpty {
                Text("Aucun déplacement.")
                    .foregroundStyle(AppTheme.muted)
            } else {
                ForEach(plan.moves.filter { !$0.needsReview }) { move in
                    moveRow(move, badge: nil)
                }
            }
        }
    }

    private func moveRow(_ move: OrganizationMove, badge: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(OrganizationPathUtils.basename(of: move.sourceRelativePath))
                        .font(CNFont.callout.weight(.semibold))
                        .strikethrough(move.excluded)
                    Text("\(shortPath(move.sourceRelativePath)) → \(shortPath(move.destinationRelativePath))")
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.mutedForeground)
                        .strikethrough(move.excluded)
                    Text(move.reason)
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.filesAccent.opacity(0.18), in: Capsule())
                            .foregroundStyle(AppTheme.filesAccent)
                    }
                    Button {
                        engine.toggleExclude(moveId: move.id)
                        AppHaptics.selection()
                    } label: {
                        Image(systemName: move.excluded ? "plus.circle" : "minus.circle")
                            .foregroundStyle(move.excluded ? AppTheme.success : AppTheme.danger)
                    }
                    .accessibilityLabel(move.excluded ? "Réinclure le fichier" : "Exclure le fichier")
                }
            }
        }
        .padding(AppTheme.space12)
        .background(
            AppTheme.surfaceElevated.opacity(move.excluded ? 0.4 : 0.9),
            in: RoundedRectangle(cornerRadius: AppTheme.radiusSm, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(OrganizationPathUtils.basename(of: move.sourceRelativePath)), de \(shortPath(move.sourceRelativePath)) vers \(shortPath(move.destinationRelativePath))"
        )
    }

    private var refineSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.space8) {
            Text("Affiner en langage naturel")
                .font(CNFont.headline)
            TextField("Ex. : mets les PDF dans Factures 2024", text: $refineText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Instruction d’affinage")
            Button {
                let text = refineText
                refineText = ""
                engine.refine(instruction: text, client: client)
            } label: {
                Label("Relancer l’analyse", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(refineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .tint(AppTheme.filesAccent)
            .accessibilityLabel("Relancer l’analyse avec l’instruction")
        }
    }

    private var reminderBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(AppTheme.filesAccent)
            Text("Rappel : aucune suppression. Seuls des déplacements et créations de dossiers seront effectués après validation explicite.")
                .font(CNFont.caption)
                .foregroundStyle(AppTheme.mutedForeground)
        }
        .padding(AppTheme.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.filesAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.radiusSm, style: .continuous))
        .accessibilityLabel("Rappel : aucune suppression")
    }

    private var approveButton: some View {
        Button {
            Task {
                AppHaptics.medium()
                await engine.approveAndExecute(client: client)
                if engine.phase == .completed || engine.phase == .partiallyCompleted {
                    await onFinished?()
                }
            }
        } label: {
            Text("Valider et réorganiser")
                .font(CNFont.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.touchMin)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.filesAccent)
        .disabled(engine.plan?.executableMoves.isEmpty == true)
        .accessibilityLabel("Valider et réorganiser")
        .accessibilityHint("Exécute les déplacements automatiques validés")
    }

    private func shortPath(_ path: String) -> String {
        let n = OrganizationPathUtils.normalize(path)
        if n.count <= 42 { return n.isEmpty ? "/" : n }
        return "…" + n.suffix(40)
    }
}
