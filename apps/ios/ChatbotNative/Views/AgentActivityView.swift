import SwiftUI

struct AgentPlanStep: Identifiable, Equatable {
    let id: String
    var title: String
    var status: String // pending | running | done | error | skipped
}

/// Snapshot persisté avec le message assistant (reste dans la conversation).
struct AgentRunSnapshot: Equatable {
    var planSteps: [AgentPlanStep] = []
    var thoughtSeconds: Int?
    var webQuery: String?
    var activitySummary: String?
    var lastError: String?
    var completed: Bool = true

    var asActivityState: AgentActivityState {
        AgentActivityState(
            phase: completed ? "synthesis" : "executing",
            stepIndex: max(0, planSteps.firstIndex(where: { $0.status == "running" }) ?? 0),
            totalSteps: planSteps.count,
            currentStepTitle: planSteps.first(where: { $0.status == "running" })?.title
                ?? planSteps.last(where: { $0.status == "done" })?.title,
            planSteps: planSteps,
            webQuery: webQuery,
            webPhase: webQuery == nil ? .idle : .done,
            lastError: lastError,
            visible: true,
            completed: completed,
            startedAt: nil,
            lockedThoughtSeconds: thoughtSeconds,
            activitySummary: activitySummary
        )
    }
}

struct AgentActivityState: Equatable {
    var phase: String = "planning"
    var stepIndex: Int = 0
    var totalSteps: Int = 0
    var currentStepTitle: String?
    var planSteps: [AgentPlanStep] = []
    var webQuery: String?
    var webPhase: WebSearchPhase = .idle
    var lastError: String?
    var visible: Bool = false
    /// Après `done` : reste inline jusqu’à attachement chrome, puis snapshot.
    var completed: Bool = false
    var startedAt: Date?
    /// Durée figée à la fin (sinon calcul live depuis startedAt).
    var lockedThoughtSeconds: Int?
    var activitySummary: String?

    func snapshot() -> AgentRunSnapshot {
        let secs: Int? = {
            if let locked = lockedThoughtSeconds { return locked }
            if let start = startedAt {
                return max(1, Int(Date().timeIntervalSince(start)))
            }
            return nil
        }()
        var steps = planSteps
        if completed {
            for i in steps.indices where steps[i].status == "running" || steps[i].status == "pending" {
                if steps[i].status == "running" { steps[i].status = "done" }
            }
        }
        return AgentRunSnapshot(
            planSteps: steps,
            thoughtSeconds: secs,
            webQuery: webQuery,
            activitySummary: activitySummary,
            lastError: lastError,
            completed: true
        )
    }
}

enum WebSearchPhase: Equatable {
    case idle, searching, analyzing, done
}

enum AgentToolLabels {
    static func humanize(_ raw: String) -> String {
        let t = raw.lowercased()
        if t.contains("web") || t.contains("search") || t.contains("searx") { return "Recherche web" }
        if t.contains("mail") || t.contains("gmail") || t.contains("email") { return "Mail" }
        if t.hasPrefix("file_") || t.contains("filesystem") || t.contains("list_files")
            || t.contains("read_file") || t == "files" || t == "file" || t.contains(" path") {
            return "Fichiers"
        }
        if t.contains("memory") || t.contains("souvenir") { return "Mémoire" }
        if t.contains("http") || t.contains("fetch") { return "Consultation" }
        if t.contains("code") || t.contains("shell") { return "Exécution" }
        let cleaned = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    static func friendlyStepTitle(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = t.lowercased()
        if lower == "comprendre la demande" || lower.hasPrefix("comprendre ") {
            return "Analyser ce que tu demandes"
        }
        if lower == "rechercher des informations" {
            return "Chercher des infos utiles"
        }
        if lower == "analyser les résultats" {
            return "Comparer ce qui a été trouvé"
        }
        if lower == "rédiger la réponse" || lower.hasPrefix("répondre") || lower.hasPrefix("repondre") {
            return "Rédiger la réponse"
        }
        if lower.hasPrefix("répondre :") || lower.hasPrefix("repondre :") {
            return "Rédiger la réponse"
        }
        // Laisser l’UI multiligne afficher le titre ; tronquer seulement les titres extrêmes.
        if t.count > 96 {
            t = String(t.prefix(93)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        if lower.contains(" ") || lower.contains("é") || lower.contains("è") || lower.contains("à") {
            return t
        }
        return humanize(t)
    }

    static func normalizeStepStatus(_ raw: String) -> String {
        switch raw.lowercased() {
        case "active", "running", "in_progress", "in-progress": return "running"
        case "done", "completed", "success", "ok": return "done"
        case "error", "failed", "failure": return "error"
        case "skipped", "skip", "cancelled", "canceled": return "skipped"
        default: return "pending"
        }
    }

    static func friendlyError(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else {
            return "Une étape n’a pas pu aboutir."
        }
        let lower = raw.lowercased()
        if lower.contains("file") || lower.contains("path") || lower.contains("fichier") {
            return "Je n’ai pas pu accéder à ce fichier."
        }
        if lower.contains("mail") || lower.contains("gmail") || lower.contains("oauth") {
            return "Je n’ai pas pu accéder à la boîte mail."
        }
        if lower.contains("network") || lower.contains("timeout") || lower.contains("fetch") {
            return "La recherche ou la connexion a échoué."
        }
        if lower.contains("permission") || lower.contains("denied") || lower.contains("403") {
            return "Action non autorisée."
        }
        if raw.count > 120 || raw.contains("Error:") || raw.contains("Exception") {
            return "Une étape a échoué. Tu peux réessayer."
        }
        return raw
    }
}

/// Panel agent — inline dans le fil (pas au-dessus du composer).
struct AgentActivityView: View {
    let state: AgentActivityState
    @State private var expanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var doneCount: Int {
        state.planSteps.filter { $0.status == "done" }.count
    }

    private var skippedCount: Int {
        state.planSteps.filter { $0.status == "skipped" }.count
    }

    private var stepsBadgeText: String {
        let base = "\(min(doneCount, max(totalCount, 1)))/\(max(totalCount, 1))"
        if skippedCount > 0 {
            return "\(base) · \(skippedCount) ignorée\(skippedCount > 1 ? "s" : "")"
        }
        return base
    }

    private var totalCount: Int {
        max(state.totalSteps, state.planSteps.count)
    }

    private var progressFraction: CGFloat {
        guard totalCount > 0 else { return state.completed ? 1 : 0 }
        if state.completed { return 1 }
        let settled = doneCount + skippedCount
        let runningBoost: CGFloat = state.planSteps.contains(where: { $0.status == "running" }) ? 0.35 : 0
        return min(1, (CGFloat(settled) + runningBoost) / CGFloat(totalCount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            thoughtHeader
            progressTrack

            if let summary = activityLine, !summary.isEmpty {
                Text(summary)
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !state.planSteps.isEmpty {
                todosCard
            } else if !state.completed {
                pendingCard
            }

            if let err = state.lastError, !err.isEmpty {
                Text(AgentToolLabels.friendlyError(err))
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.danger)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppTheme.surfaceElevated.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            AppTheme.borderSubtle,
                            AppTheme.accent.opacity(state.completed ? 0.12 : 0.28),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activité agent")
        .accessibilityIdentifier(A11yID.Agent.root)
        .onAppear {
            expanded = !state.completed
        }
    }

    private var thoughtHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TimelineView(.periodic(from: .now, by: state.completed || state.lockedThoughtSeconds != nil ? 3600 : 1)) { context in
                    Text(thoughtLabel(at: context.date))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(AppTheme.foreground.opacity(0.92))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.25), value: thoughtLabel(at: context.date))
                }
                Spacer(minLength: 0)
                if !state.completed {
                    Image(systemName: "sparkle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.accent)
                        .symbolEffect(
                            .pulse,
                            options: .repeating.speed(0.5),
                            isActive: !reduceMotion
                        )
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.mutedForeground)
                }
            }
            .accessibilityIdentifier(A11yID.Agent.step)

            if let caption = thoughtCaption, !caption.isEmpty {
                Text(caption)
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.foreground.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var progressTrack: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.borderSubtle)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent.opacity(0.85), AppTheme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, geo.size.width * progressFraction))
                    .animation(.spring(response: 0.45, dampingFraction: 0.86), value: progressFraction)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }

    private var todosCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: AppTheme.motionQuick, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
                AppHaptics.selection()
            } label: {
                HStack(spacing: 8) {
                    Text("Étapes")
                        .font(CNFont.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                    Text(stepsBadgeText)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(AppTheme.accentSubtle))
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedForeground)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(state.planSteps.enumerated()), id: \.element.id) { index, step in
                        stepRow(step, isLast: index == state.planSteps.count - 1)
                    }
                }
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityIdentifier(A11yID.Agent.timeline)
            }
        }
    }

    private var pendingCard: some View {
        HStack(spacing: 10) {
            Image(systemName: state.webPhase != .idle ? "globe" : "sparkles")
                .foregroundStyle(AppTheme.accent)
                .symbolEffect(
                    .pulse,
                    options: .repeating.speed(0.45),
                    isActive: !reduceMotion && !state.completed
                )
            Text(pendingCardTitle)
                .font(CNFont.callout)
                .foregroundStyle(AppTheme.foreground)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.surface.opacity(0.55))
        )
    }

    private var pendingCardTitle: String {
        if let title = state.currentStepTitle, !title.isEmpty {
            return AgentToolLabels.friendlyStepTitle(title)
        }
        switch state.webPhase {
        case .searching: return "Recherche web…"
        case .analyzing: return "Analyse des sources…"
        case .done: return "Sources prêtes…"
        case .idle: break
        }
        switch state.phase {
        case "synthesis", "synthesizing": return "Rédaction de la réponse…"
        case "executing": return "Exécution…"
        default: return "Préparation du plan…"
        }
    }

    private func stepRow(_ step: AgentPlanStep, isLast: Bool) -> some View {
        let status = step.status
        let title = AgentToolLabels.friendlyStepTitle(step.title)
        let running = status == "running"
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(running ? AppTheme.accentSubtle : Color.clear)
                        .frame(width: 26, height: 26)
                    Image(systemName: stepIcon(status))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(stepColor(status))
                        .symbolEffect(
                            .pulse,
                            options: .repeating.speed(0.55),
                            isActive: !reduceMotion && running
                        )
                }
                if !isLast {
                    Rectangle()
                        .fill(AppTheme.borderSubtle)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 26)

            Text(title)
                .font(CNFont.callout.weight(running ? .semibold : .regular))
                .foregroundStyle(stepTitleColor(status))
                .strikethrough(status == "done" || status == "skipped", color: AppTheme.mutedForeground.opacity(0.55))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, isLast ? 0 : 14)

            Spacer(minLength: 0)
        }
        .accessibilityLabel("\(title), \(statusLabel(status))")
    }

    private var activityLine: String? {
        if let summary = state.activitySummary, !summary.isEmpty { return summary }
        if state.webPhase != .idle, let q = state.webQuery, !q.isEmpty {
            switch state.webPhase {
            case .searching: return "Recherche · \(q)"
            case .analyzing: return "Analyse des sources · \(q)"
            case .done: return "Recherche · \(q)"
            case .idle: return nil
            }
        }
        return nil
    }

    private var thoughtCaption: String? {
        if state.completed {
            if let err = state.lastError, !err.isEmpty {
                return AgentToolLabels.friendlyError(err)
            }
            return nil
        }
        if let title = state.currentStepTitle, !title.isEmpty {
            return AgentToolLabels.friendlyStepTitle(title)
        }
        switch state.webPhase {
        case .searching: return "Recherche web…"
        case .analyzing: return "Analyse des sources…"
        case .done: return "Sources collectées"
        case .idle: break
        }
        switch state.phase {
        case "planning": return "Préparation du plan…"
        case "synthesis", "synthesizing": return "Rédaction de la réponse…"
        default: return nil
        }
    }

    private func thoughtLabel(at date: Date) -> String {
        let secs: Int
        if let locked = state.lockedThoughtSeconds {
            secs = locked
        } else if let start = state.startedAt {
            secs = max(0, Int(date.timeIntervalSince(start)))
        } else {
            return state.completed ? "Réflexion" : "Réflexion…"
        }
        return "Réflexion \(secs)s"
    }

    private func stepIcon(_ status: String) -> String {
        switch status {
        case "done": return "checkmark.circle.fill"
        case "running": return "circle.inset.filled"
        case "error": return "xmark.circle.fill"
        case "skipped": return "minus.circle"
        default: return "circle"
        }
    }

    private func stepColor(_ status: String) -> Color {
        switch status {
        case "done": return AppTheme.accent.opacity(0.75)
        case "running": return AppTheme.accent
        case "error": return AppTheme.danger
        case "skipped": return AppTheme.mutedForeground.opacity(0.55)
        default: return AppTheme.mutedForeground.opacity(0.55)
        }
    }

    private func stepTitleColor(_ status: String) -> Color {
        switch status {
        case "running": return AppTheme.foreground
        case "error": return AppTheme.danger
        case "done", "skipped", "pending": return AppTheme.mutedForeground
        default: return AppTheme.mutedForeground
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "done": return "terminé"
        case "running": return "en cours"
        case "error": return "erreur"
        case "skipped": return "ignoré"
        default: return "à faire"
        }
    }
}

typealias AgentStrip = AgentActivityView
