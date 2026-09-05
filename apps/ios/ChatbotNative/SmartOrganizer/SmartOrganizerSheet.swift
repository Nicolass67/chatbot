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
                    if isBusy {
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

    private var isBusy: Bool {
        switch engine.phase {
        case .inventorying, .analyzing, .proposing, .validating, .executing:
            return true
        default:
            return false
        }
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
            if engine.phase == .executing {
                Text("Déplacements uniquement — aucune suppression.")
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

                if let result = engine.executionResult {
                    Text("\(result.succeededCount) OK · \(result.failedCount) échec\(result.failedCount > 1 ? "s" : "")")
                        .font(CNFont.callout)
                        .foregroundStyle(AppTheme.mutedForeground)
                }

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

    // MARK: - Proposal

    private var proposalView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.space16) {
                    if let plan = engine.plan {
                        compactHeader(plan)
                        quickActions(plan)
                        movesList(plan)
                        refineBox
                        Text("Aucune suppression — validation requise avant exécution.")
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                }
                .padding(AppTheme.space16)
                .padding(.bottom, 88)
            }
            approveBar
        }
    }

    private func compactHeader(_ plan: OrganizationPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plan.summary)
                .font(CNFont.callout.weight(.medium))
                .foregroundStyle(AppTheme.foreground)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                metricPill("\(plan.executableMoves.count)", caption: "auto", tint: AppTheme.filesAccent)
                metricPill("\(plan.reviewMoves.count)", caption: "revue", tint: AppTheme.warning)
                metricPill("\(plan.proposedDirectories.count)", caption: "dossiers", tint: AppTheme.mutedForeground)
                metricPill("\(plan.excludedCount)", caption: "exclus", tint: AppTheme.danger)
            }
        }
        .padding(AppTheme.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(plan.executableMoves.count) automatiques, \(plan.reviewMoves.count) à revoir, \(plan.excludedCount) exclus"
        )
    }

    private func metricPill(_ value: String, caption: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(CNFont.headline)
                .foregroundStyle(tint)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(AppTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func quickActions(_ plan: OrganizationPlan) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if !plan.reviewMoves.isEmpty {
                    actionChip("Tout accepter", systemImage: "checkmark.circle") {
                        engine.acceptAllReviews()
                        AppHaptics.selection()
                    }
                }
                actionChip("Tout inclure", systemImage: "plus.circle") {
                    engine.includeAll()
                    AppHaptics.selection()
                }
                actionChip("Tout exclure", systemImage: "minus.circle") {
                    engine.excludeAll()
                    AppHaptics.selection()
                }
                if plan.protectedStructures.contains(where: { $0.level == .protected }) {
                    Label("Protégé", systemImage: "lock.fill")
                        .font(CNFont.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.filesAccent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(AppTheme.filesAccent.opacity(0.12), in: Capsule())
                }
            }
        }
        .accessibilityLabel("Actions rapides")
    }

    private func actionChip(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(CNFont.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(AppTheme.filesAccent)
        .accessibilityLabel(title)
    }

    private func movesList(_ plan: OrganizationPlan) -> some View {
        let review = plan.reviewMovesIncludingExcluded
        let auto = plan.autoMovesIncludingExcluded

        return VStack(alignment: .leading, spacing: AppTheme.space14) {
            if !review.isEmpty {
                sectionTitle("À revoir", count: review.filter { !$0.excluded }.count)
                ForEach(review) { move in
                    moveCard(move, kind: .review)
                }
            }
            if !auto.isEmpty {
                sectionTitle("Propositions", count: auto.filter { !$0.excluded }.count)
                ForEach(auto) { move in
                    moveCard(move, kind: .auto)
                }
            }
            if plan.moves.isEmpty {
                Text("Aucune proposition.")
                    .foregroundStyle(AppTheme.muted)
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(CNFont.headline)
            Spacer()
            Text("\(count)")
                .font(CNFont.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(AppTheme.surfaceElevated, in: Capsule())
        }
    }

    private enum MoveKind { case review, auto }

    private func moveCard(_ move: OrganizationMove, kind: MoveKind) -> some View {
        let excluded = move.excluded
        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(OrganizationPathUtils.basename(of: move.sourceRelativePath))
                    .font(CNFont.callout.weight(.semibold))
                    .foregroundStyle(excluded ? AppTheme.muted : AppTheme.foreground)
                    .strikethrough(excluded, color: AppTheme.muted)
                    .lineLimit(2)

                Text("\(shortPath(move.sourceRelativePath))  →  \(shortPath(move.destinationRelativePath))")
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.mutedForeground)
                    .strikethrough(excluded, color: AppTheme.muted)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if kind == .review && !excluded {
                        statusChip("Revue", tint: AppTheme.warning)
                    }
                    if excluded {
                        statusChip("Exclu", tint: AppTheme.danger)
                    }
                    Text(move.reason)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(spacing: 8) {
                if kind == .review && !excluded {
                    Button {
                        engine.acceptReview(moveId: move.id)
                        AppHaptics.selection()
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(AppTheme.success)
                    }
                    .accessibilityLabel("Accepter ce déplacement")
                }

                Button {
                    engine.toggleExclude(moveId: move.id)
                    AppHaptics.selection()
                } label: {
                    Image(systemName: excluded ? "arrow.uturn.backward.circle.fill" : "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(excluded ? AppTheme.filesAccent : AppTheme.danger)
                }
                .accessibilityLabel(excluded ? "Réinclure le fichier" : "Exclure le fichier")
            }
        }
        .padding(AppTheme.space12)
        .background(
            AppTheme.surfaceElevated.opacity(excluded ? 0.35 : 0.92),
            in: RoundedRectangle(cornerRadius: AppTheme.radiusSm, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusSm, style: .continuous)
                .strokeBorder(excluded ? AppTheme.danger.opacity(0.25) : Color.clear, lineWidth: 1)
        )
        .opacity(excluded ? 0.72 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityMoveLabel(move, excluded: excluded))
        .accessibilityHint(excluded ? "Exclu de la réorganisation" : "Inclus dans la réorganisation")
    }

    private func statusChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.16), in: Capsule())
    }

    private var refineBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Affiner")
                .font(CNFont.headline)
            HStack(spacing: 8) {
                TextField("Ex. : PDF → Factures 2024", text: $refineText)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.go)
                    .onSubmit { runRefine() }
                    .accessibilityLabel("Instruction d’affinage")

                Button {
                    runRefine()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.filesAccent)
                .disabled(refineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Relancer l’analyse")
            }
        }
    }

    private var approveBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            Button {
                Task {
                    AppHaptics.medium()
                    await engine.approveAndExecute(client: client)
                    if engine.phase == .completed || engine.phase == .partiallyCompleted {
                        await onFinished?()
                    }
                }
            } label: {
                Text(approveTitle)
                    .font(CNFont.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.touchMin)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.filesAccent)
            .disabled(engine.plan?.executableMoves.isEmpty == true)
            .padding(.horizontal, AppTheme.space16)
            .padding(.vertical, 10)
            .background(AppTheme.surface.opacity(0.96))
            .accessibilityLabel("Valider et réorganiser")
            .accessibilityHint("Exécute uniquement les déplacements non exclus")
        }
    }

    private var approveTitle: String {
        let n = engine.plan?.executableMoves.count ?? 0
        if n == 0 { return "Rien à exécuter" }
        return "Valider · \(n) déplacement\(n > 1 ? "s" : "")"
    }

    private func runRefine() {
        let text = refineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        refineText = ""
        engine.refine(instruction: text, client: client)
        AppHaptics.light()
    }

    private func accessibilityMoveLabel(_ move: OrganizationMove, excluded: Bool) -> String {
        let name = OrganizationPathUtils.basename(of: move.sourceRelativePath)
        let state = excluded ? "exclu" : "inclus"
        return "\(name), \(state), vers \(shortPath(move.destinationRelativePath))"
    }

    private func shortPath(_ path: String) -> String {
        let n = OrganizationPathUtils.normalize(path)
        if n.count <= 36 { return n.isEmpty ? "/" : n }
        return "…" + n.suffix(34)
    }
}
