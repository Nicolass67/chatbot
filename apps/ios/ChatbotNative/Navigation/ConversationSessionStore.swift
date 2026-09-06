import Foundation

/// Persistance des 3 contextes conversationnels (Chat / Mail / Files).
/// Fermer un panel ≠ supprimer la conversation — seul « Nouveau chat » réinitialise.
@MainActor
enum ConversationSessionStore {
    nonisolated static let globalContextKey = "__global__"

    private static let generalKey = "ctxchat.general.active"

    private static func scopedKey(scope: ConversationScope, contextKey: String?) -> String {
        let key = (contextKey?.isEmpty == false) ? contextKey! : globalContextKey
        switch scope {
        case .general:
            return generalKey
        case .mail:
            return "ctxchat.mail.\(key)"
        case .files:
            return "ctxchat.file.\(key)"
        }
    }

    static func conversationId(scope: ConversationScope, contextKey: String? = nil) -> String? {
        UserDefaults.standard.string(forKey: scopedKey(scope: scope, contextKey: contextKey))
    }

    static func save(conversationId: String, scope: ConversationScope, contextKey: String? = nil) {
        UserDefaults.standard.set(
            conversationId,
            forKey: scopedKey(scope: scope, contextKey: contextKey)
        )
    }

    /// Uniquement pour « Nouveau chat » explicite.
    static func clear(scope: ConversationScope, contextKey: String? = nil) {
        let storage = scopedKey(scope: scope, contextKey: contextKey)
        if let id = UserDefaults.standard.string(forKey: storage) {
            chromeMemory.removeValue(forKey: id)
            draftCardMemory.removeValue(forKey: id)
        }
        UserDefaults.standard.removeObject(forKey: storage)
    }

    static func clear(conversationId: String, scope: ConversationScope, contextKey: String? = nil) {
        UserDefaults.standard.removeObject(forKey: scopedKey(scope: scope, contextKey: contextKey))
        chromeMemory.removeValue(forKey: conversationId)
        draftCardMemory.removeValue(forKey: conversationId)
    }

    // MARK: - Chrome structuré (filesFound, drafts meta, handoffs) en mémoire process

    private static var chromeMemory: [String: [String: MessageChromeMeta]] = [:]

    static func chrome(for conversationId: String) -> [String: MessageChromeMeta] {
        chromeMemory[conversationId] ?? [:]
    }

    /// Remplace la map chrome (après prune fenêtre historique).
    static func replaceChrome(conversationId: String, chrome: [String: MessageChromeMeta]) {
        if chrome.isEmpty {
            chromeMemory.removeValue(forKey: conversationId)
        } else {
            chromeMemory[conversationId] = chrome
        }
    }

    static func setChrome(
        _ meta: MessageChromeMeta,
        conversationId: String,
        messageId: String
    ) {
        var map = chromeMemory[conversationId] ?? [:]
        map[messageId] = meta
        chromeMemory[conversationId] = map
    }

    static func mergeChrome(
        _ patch: MessageChromeMeta,
        conversationId: String,
        messageId: String
    ) {
        var existing = chromeMemory[conversationId]?[messageId] ?? MessageChromeMeta()
        if !patch.sources.isEmpty { existing.sources = patch.sources }
        if patch.mailHandoff != nil { existing.mailHandoff = patch.mailHandoff }
        if patch.filesHandoff != nil { existing.filesHandoff = patch.filesHandoff }
        if !patch.filesFound.isEmpty { existing.filesFound = patch.filesFound }
        if patch.agentRun != nil { existing.agentRun = patch.agentRun }
        if !patch.savedMemories.isEmpty {
            existing.savedMemories = Self.mergeSavedMemories(existing.savedMemories, patch.savedMemories)
        }
        setChrome(existing, conversationId: conversationId, messageId: messageId)
    }

    /// Après reload serveur : transfère le chrome d’un ID temporaire vers l’ID serveur.
    static func remountChrome(
        conversationId: String,
        from temporaryId: String,
        onto serverMessages: [MessageDTO]
    ) -> [String: MessageChromeMeta] {
        var map = chromeMemory[conversationId] ?? [:]
        guard let temp = map[temporaryId] else { return map }
        // Dernier message assistant serveur
        if let last = serverMessages.last(where: { $0.role == "assistant" }) {
            var merged = map[last.id] ?? MessageChromeMeta()
            if !temp.sources.isEmpty { merged.sources = temp.sources }
            if temp.mailHandoff != nil { merged.mailHandoff = temp.mailHandoff }
            if temp.filesHandoff != nil { merged.filesHandoff = temp.filesHandoff }
            if !temp.filesFound.isEmpty { merged.filesFound = temp.filesFound }
            // Ne pas écraser un panel agent déjà finalisé sur un autre message.
            if temp.agentRun != nil, merged.agentRun == nil || last.id == temporaryId {
                merged.agentRun = temp.agentRun
            }
            if !temp.savedMemories.isEmpty {
                merged.savedMemories = Self.mergeSavedMemories(merged.savedMemories, temp.savedMemories)
            }
            map[last.id] = merged
            if last.id != temporaryId {
                map.removeValue(forKey: temporaryId)
            }
            chromeMemory[conversationId] = map
        }
        return map
    }

    // MARK: - Draft card snapshot (survit au kill app via UserDefaults)

    struct DraftCardSnapshot: Codable, Equatable {
        var draftId: String?
        var text: String
        var to: String
        var subject: String
        var status: String
        var sent: Bool
        var inConversation: Bool
    }

    private static let draftCardDefaultsPrefix = "ctxchat.draftCard."
    private static var draftCardMemory: [String: DraftCardSnapshot] = [:]

    private static func draftCardDefaultsKey(_ conversationId: String) -> String {
        draftCardDefaultsPrefix + conversationId
    }

    static func draftCard(conversationId: String) -> DraftCardSnapshot? {
        if let mem = draftCardMemory[conversationId] { return mem }
        guard let data = UserDefaults.standard.data(forKey: draftCardDefaultsKey(conversationId)),
              let snap = try? JSONDecoder().decode(DraftCardSnapshot.self, from: data)
        else { return nil }
        draftCardMemory[conversationId] = snap
        return snap
    }

    static func saveDraftCard(conversationId: String, _ snap: DraftCardSnapshot) {
        draftCardMemory[conversationId] = snap
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: draftCardDefaultsKey(conversationId))
        }
    }

    static func clearDraftCard(conversationId: String) {
        draftCardMemory.removeValue(forKey: conversationId)
        UserDefaults.standard.removeObject(forKey: draftCardDefaultsKey(conversationId))
    }
}

extension ConversationSessionStore {
    static func mergeSavedMemories(
        _ existing: [SavedMemoryChipDTO],
        _ incoming: [SavedMemoryChipDTO]
    ) -> [SavedMemoryChipDTO] {
        var byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for item in incoming {
            byId[item.id] = item
        }
        return Array(byId.values)
    }
}
