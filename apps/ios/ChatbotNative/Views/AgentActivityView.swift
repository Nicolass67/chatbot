import SwiftUI

struct AgentPlanStep: Identifiable, Equatable {
    let id: String
    var title: String
    var status: String // pending | running | done | error
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
        if lower.contains(" ") || lower.contains("é") || lower.contains("è") || lower.contains("à") {
            if t.count > 48 {
                t = String(t.prefix(45)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            }
            return t
        }
        if t.count > 48 {
            t = String(t.prefix(45)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
        }
        return humanize(t)
    }

    static func normalizeStepStatus(_ raw: String) -> String {
        switch raw.lowercased() {
        case "active", "running", "in_progress", "in-progress": return "running"
        case "done", "completed", "success", "ok": return "done"
        case "error", "failed", "failure": return "error"
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

/// Panel agent style Cursor — inline dans le fil (pas au-dessus du composer).
struct AgentActivityView: View {
    let state: AgentActivityState
    @State private var expanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var doneCount: Int {
        state.planSteps.filter { $0.status == "done" }.count
    }

    private var totalCount: Int {
        max(state.totalSteps, state.planSteps.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            thoughtHeader

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activité agent")
        .accessibilityIdentifier(A11yID.Agent.root)
        .onAppear {
            expanded = !state.completed
        }
        .onChange(of: state.completed) { _, done in
            // Terminé : on laisse le panel ouvert comme Cursor (repliable).
            if done { /* keep user preference */ }
        }
    }

    private var thoughtHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: .now, by: state.completed ? 3600 : 1)) { context in
                Text(thoughtLabel(at: context.date))
                    .font(CNFont.caption.weight(.medium))
                    .foregroundStyle(AppTheme.mutedForeground)
            }
            if let caption = thoughtCaption, !caption.isEmpty {
                Text(caption)
                    .font(CNFont.callout)
                    .foregroundStyle(AppTheme.foreground.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier(A11yID.Agent.step)
    }

    private var todosCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: AppTheme.motionQuick, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
                AppHaptics.selection()
            } label: {
                HStack {
                    Text("Étapes \(min(doneCount, max(totalCount, 1)))/\(max(totalCount, 1))")
                        .font(CNFont.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedForeground)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(state.planSteps) { step in
                        stepRow(step)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityIdentifier(A11yID.Agent.timeline)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.surfaceElevated.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 0.5)
        )
    }

    private var pendingCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(AppTheme.accent)
                .symbolEffect(
                    .pulse,
                    options: .repeating.speed(0.45),
                    isActive: !reduceMotion && !state.completed
                )
            Text(state.currentStepTitle.map(AgentToolLabels.friendlyStepTitle) ?? "Préparation du plan…")
                .font(CNFont.callout)
                .foregroundStyle(AppTheme.foreground)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.surfaceElevated.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 0.5)
        )
    }

    private func stepRow(_ step: AgentPlanStep) -> some View {
        let status = step.status
        let title = AgentToolLabels.friendlyStepTitle(step.title)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: stepIcon(status))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(stepColor(status))
                .symbolEffect(
                    .pulse,
                    options: .repeating.speed(0.55),
                    isActive: !reduceMotion && status == "running"
                )
                .frame(width: 18)
            Text(title)
                .font(CNFont.callout)
                .foregroundStyle(status == "done" || status == "pending" ? AppTheme.mutedForeground : AppTheme.foreground)
                .strikethrough(status == "done", color: AppTheme.mutedForeground)
                .lineLimit(2)
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
        case "running": return "arrow.forward.circle.fill"
        case "error": return "xmark.circle.fill"
        default: return "circle"
        }
    }

    private func stepColor(_ status: String) -> Color {
        switch status {
        case "done": return AppTheme.mutedForeground
        case "running": return AppTheme.foreground
        case "error": return AppTheme.danger
        default: return AppTheme.mutedForeground.opacity(0.7)
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "done": return "terminé"
        case "running": return "en cours"
        case "error": return "erreur"
        default: return "à faire"
        }
    }
}

typealias AgentStrip = AgentActivityView
