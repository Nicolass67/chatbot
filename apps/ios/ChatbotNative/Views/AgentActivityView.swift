import SwiftUI

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
    /// Après `done` : bandeau réduit puis disparaît.
    var completed: Bool = false
}

struct AgentPlanStep: Identifiable, Equatable {
    let id: String
    var title: String
    var status: String // pending | running | done | error
}

enum WebSearchPhase: Equatable {
    case idle, searching, analyzing, done
}

enum AgentToolLabels {
    static func humanize(_ raw: String) -> String {
        let t = raw.lowercased()
        if t.contains("web") || t.contains("search") { return "Recherche web" }
        if t.contains("mail") || t.contains("gmail") || t.contains("email") { return "Mail" }
        if t.contains("file") || t.contains("path") { return "Fichiers" }
        if t.contains("memory") || t.contains("souvenir") { return "Mémoire" }
        if t.contains("http") || t.contains("fetch") { return "Consultation" }
        if t.contains("code") || t.contains("shell") { return "Exécution" }
        // Nettoie snake_case / CamelCase
        let cleaned = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    /// Titres d’étapes lisibles (pas la requête user entière).
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

/// Timeline Agent compacte — expand auto pendant le travail ; collapse après completion.
struct AgentActivityView: View {
    let state: AgentActivityState
    @State private var expanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summaryLine: String {
        if let err = state.lastError, !err.isEmpty {
            return AgentToolLabels.friendlyError(err)
        }
        if state.completed {
            return "Terminé"
        }
        if state.webPhase == .searching, let q = state.webQuery {
            return "Recherche · \(q)"
        }
        if state.webPhase == .analyzing {
            return "Analyse des sources…"
        }
        if let title = state.currentStepTitle, !title.isEmpty {
            return AgentToolLabels.friendlyStepTitle(title)
        }
        switch state.phase {
        case "planning": return "Préparation du plan…"
        case "executing":
            if state.totalSteps > 0 {
                return "Étape \(min(state.stepIndex + 1, state.totalSteps))/\(state.totalSteps)"
            }
            return "Travail en cours…"
        case "synthesis", "synthesizing": return "Rédaction de la réponse…"
        default: return "Agent actif"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: AppTheme.motionQuick, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
                AppHaptics.light()
            } label: {
                HStack(spacing: AppTheme.space12) {
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(state.lastError != nil ? AppTheme.danger : AppTheme.accent)
                        .symbolEffect(
                            .pulse,
                            options: .repeating.speed(0.45),
                            isActive: !reduceMotion && state.visible && !state.completed && state.lastError == nil
                        )
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(summaryLine)
                            .font(CNFont.callout.weight(.medium))
                            .foregroundStyle(AppTheme.foreground)
                            .lineLimit(2)
                        Text(state.completed ? "Terminé" : progressCaption)
                            .font(CNFont.caption2)
                            .foregroundStyle(AppTheme.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.mutedForeground)
                }
                .padding(.horizontal, AppTheme.space16)
                .padding(.vertical, AppTheme.space12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(summaryLine)
            .accessibilityIdentifier(A11yID.Agent.step)

            if expanded {
                VStack(alignment: .leading, spacing: AppTheme.space8) {
                    if state.webPhase != .idle, let q = state.webQuery {
                        HStack(spacing: AppTheme.space8) {
                            Image(systemName: webIcon)
                                .foregroundStyle(AppTheme.accent)
                            Text(q)
                                .font(CNFont.caption)
                                .foregroundStyle(AppTheme.muted)
                                .lineLimit(2)
                        }
                    }
                    if !state.planSteps.isEmpty {
                        ForEach(state.planSteps) { step in
                            HStack(alignment: .top, spacing: AppTheme.space8) {
                                Image(systemName: stepIcon(step.status))
                                    .font(.caption)
                                    .foregroundStyle(stepColor(step.status))
                                    .symbolEffect(
                                        .pulse,
                                        options: .repeating.speed(0.55),
                                        isActive: !reduceMotion && step.status == "running"
                                    )
                                    .frame(width: 16)
                                Text(AgentToolLabels.friendlyStepTitle(step.title))
                                    .font(CNFont.caption.weight(step.status == "running" ? .semibold : .regular))
                                    .foregroundStyle(
                                        step.status == "pending"
                                            ? AppTheme.mutedForeground
                                            : AppTheme.foreground
                                    )
                                    .lineLimit(2)
                            }
                        }
                    } else if state.totalSteps > 0 && !state.completed {
                        ProgressView(
                            value: Double(state.stepIndex + 1),
                            total: Double(max(1, state.totalSteps))
                        )
                        .tint(AppTheme.accent)
                    }
                    if let err = state.lastError {
                        Text(AgentToolLabels.friendlyError(err))
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.danger)
                    }
                }
                .padding(.horizontal, AppTheme.space16)
                .padding(.bottom, AppTheme.space12)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityIdentifier(A11yID.Agent.timeline)
            }
        }
        .chromeGlass(cornerRadius: AppTheme.radiusLg, opacity: 0.4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activité agent")
        .accessibilityIdentifier(A11yID.Agent.root)
        .opacity(state.completed ? 0.72 : 1)
        .onAppear {
            expanded = !state.completed
        }
        .onChange(of: state.completed) { _, done in
            if done {
                withAnimation(.easeOut(duration: 0.2)) { expanded = false }
            }
        }
        .onChange(of: state.stepIndex) { _, _ in
            if !state.completed { expanded = true }
        }
        .onChange(of: state.currentStepTitle) { _, _ in
            if !state.completed { expanded = true }
        }
    }

    private var progressCaption: String {
        let done = state.planSteps.filter { $0.status == "done" }.count
        if state.totalSteps > 0 {
            return "\(done)/\(state.totalSteps) étapes"
        }
        return "Activité"
    }

    private var iconName: String {
        if state.lastError != nil { return "exclamationmark.triangle.fill" }
        if state.completed { return "checkmark.circle.fill" }
        if state.webPhase == .searching { return "globe" }
        return "sparkles"
    }

    private var webIcon: String {
        switch state.webPhase {
        case .searching: return "magnifyingglass"
        case .analyzing: return "doc.text.magnifyingglass"
        case .done: return "checkmark"
        case .idle: return "globe"
        }
    }

    private func stepIcon(_ status: String) -> String {
        switch status {
        case "done": return "checkmark.circle.fill"
        case "running": return "circle.dotted"
        case "error": return "xmark.circle.fill"
        default: return "circle"
        }
    }

    private func stepColor(_ status: String) -> Color {
        switch status {
        case "done": return AppTheme.success
        case "running": return AppTheme.accent
        case "error": return AppTheme.danger
        default: return AppTheme.mutedForeground
        }
    }
}

typealias AgentStrip = AgentActivityView
