import SwiftUI

enum ConversationScope: String, Codable, Hashable, Sendable, CaseIterable {
    case general
    case mail
    case files

    var historyTitle: String {
        switch self {
        case .general: return "Conversations"
        case .mail: return "Conversations Mail"
        case .files: return "Conversations Files"
        }
    }

    var emptyHistoryMessage: String {
        switch self {
        case .general: return "Aucune conversation générale pour l’instant."
        case .mail: return "Aucune conversation concernant vos mails."
        case .files: return "Aucune conversation concernant vos fichiers."
        }
    }
}

struct ActiveContextHint: Hashable, Sendable {
    var fileId: String?
    var mailThreadId: String?
    var rootId: String?
    var label: String?

    func asDictionary() -> [String: Any] {
        var d: [String: Any] = [:]
        if let fileId { d["fileId"] = fileId }
        if let mailThreadId { d["mailThreadId"] = mailThreadId }
        if let rootId { d["rootId"] = rootId }
        if let label { d["label"] = label }
        return d
    }

    var isEmpty: Bool {
        fileId == nil && mailThreadId == nil && rootId == nil && (label?.isEmpty ?? true)
    }
}

enum FilesAssistantContext: Equatable {
    case global
    case folder(rootId: String, path: String, title: String)
    case file(fileId: String, name: String, rootId: String, path: String)

    var sheetTitle: String {
        switch self {
        case .global: return "Files Assistant"
        case .folder(_, _, let title): return "Assistant · \(title)"
        case .file(_, let name, _, _): return "Assistant · \(name)"
        }
    }

    var label: String {
        switch self {
        case .global: return "Tous vos fichiers"
        case .folder(_, let path, let title): return path.isEmpty ? title : path
        case .file(_, let name, _, _): return name
        }
    }

    var ref: ActiveContextHint {
        switch self {
        case .global:
            return ActiveContextHint(label: "Files")
        case .folder(let rootId, let path, let title):
            return ActiveContextHint(rootId: rootId, label: path.isEmpty ? title : path)
        case .file(let fileId, let name, let rootId, _):
            return ActiveContextHint(fileId: fileId, rootId: rootId, label: name)
        }
    }

    /// Une seule conversation Files pour tout le navigateur (racine + dossiers).
    /// Le dossier courant reste dans `ref` pour le contexte IA — fermer/rouvrir
    /// ou changer de dossier ne recrée plus un chat vide.
    var persistenceKey: String {
        ConversationSessionStore.globalContextKey
    }
}

enum MailAssistantContext: Equatable {
    case global
    case thread(threadId: String, subject: String, from: String?)

    var sheetTitle: String {
        switch self {
        case .global: return "Mail Assistant"
        case .thread(_, let subject, _):
            let s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? "Assistant · Mail" : "Assistant · \(String(s.prefix(40)))"
        }
    }

    var label: String {
        switch self {
        case .global: return "Boîte mail"
        case .thread(_, let subject, let from):
            let s = subject.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { return from ?? "Mail" }
            return s
        }
    }

    var ref: ActiveContextHint {
        switch self {
        case .global:
            return ActiveContextHint(label: "Mail")
        case .thread(let threadId, let subject, _):
            return ActiveContextHint(mailThreadId: threadId, label: subject)
        }
    }

    var persistenceKey: String {
        switch self {
        case .global:
            return ConversationSessionStore.globalContextKey
        case .thread(let threadId, _, _):
            return threadId
        }
    }
}

/// Bouton signature Assistant contextuel (FAB) — chrome glass, accent de scope.
struct ContextualAssistantButton: View {
    var accessibilityId: String = A11yID.Assistant.open
    var accessibilityLabelText: String = "Ouvrir l’assistant"
    var tint: Color = AppTheme.accent
    var action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    AppHaptics.light()
                    action()
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 54, height: 54)
                        .background {
                            if reduceTransparency {
                                Circle().fill(AppTheme.surfaceElevated)
                            } else {
                                Circle().fill(.ultraThinMaterial)
                            }
                        }
                        .overlay(Circle().stroke(tint.opacity(0.45), lineWidth: 1.25))
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabelText)
                .accessibilityIdentifier(accessibilityId)
                .accessibilityAddTraits(.isButton)
                .padding(.trailing, 18)
                .padding(.bottom, 18)
                .allowsHitTesting(true)
            }
    }
}
