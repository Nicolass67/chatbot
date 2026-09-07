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
            UserDefaults.standard.removeObject(forKey: chromeDefaultsKey(id))
            UserDefaults.standard.removeObject(forKey: draftCardDefaultsKey(id))
        }
        UserDefaults.standard.removeObject(forKey: storage)
    }

    static func clear(conversationId: String, scope: ConversationScope, contextKey: String? = nil) {
        UserDefaults.standard.removeObject(forKey: scopedKey(scope: scope, contextKey: contextKey))
        chromeMemory.removeValue(forKey: conversationId)
        draftCardMemory.removeValue(forKey: conversationId)
        UserDefaults.standard.removeObject(forKey: chromeDefaultsKey(conversationId))
        UserDefaults.standard.removeObject(forKey: draftCardDefaultsKey(conversationId))
    }

    // MARK: - Chrome structuré (filesFound persistant disk comme les brouillons)

    private static var chromeMemory: [String: [String: MessageChromeMeta]] = [:]
    private static let chromeDefaultsPrefix = "ctxchat.chrome."

    private struct PersistedChromeSlice: Codable {
        var filesFound: [FilesFoundFileDTO]
        var savedMemories: [SavedMemoryChipDTO]
    }

    private static func chromeDefaultsKey(_ conversationId: String) -> String {
        chromeDefaultsPrefix + conversationId
    }

    private static func loadChromeFromDisk(_ conversationId: String) -> [String: MessageChromeMeta]? {
        guard let data = UserDefaults.standard.data(forKey: chromeDefaultsKey(conversationId)),
              let raw = try? JSONDecoder().decode([String: PersistedChromeSlice].self, from: data)
        else { return nil }
        var map: [String: MessageChromeMeta] = [:]
        for (messageId, slice) in raw {
            guard !slice.filesFound.isEmpty || !slice.savedMemories.isEmpty else { continue }
            map[messageId] = MessageChromeMeta(
                filesFound: slice.filesFound,
                savedMemories: slice.savedMemories
            )
        }
        return map.isEmpty ? nil : map
    }

    private static func persistChromeToDisk(_ conversationId: String) {
        let map = chromeMemory[conversationId] ?? [:]
        var payload: [String: PersistedChromeSlice] = [:]
        for (messageId, meta) in map {
            guard !meta.filesFound.isEmpty || !meta.savedMemories.isEmpty else { continue }
            payload[messageId] = PersistedChromeSlice(
                filesFound: meta.filesFound,
                savedMemories: meta.savedMemories
            )
        }
        let key = chromeDefaultsKey(conversationId)
        if payload.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func chrome(for conversationId: String) -> [String: MessageChromeMeta] {
        if let mem = chromeMemory[conversationId] { return mem }
        if let disk = loadChromeFromDisk(conversationId) {
            chromeMemory[conversationId] = disk
            return disk
        }
        return [:]
    }

    /// Remplace la map chrome (après prune fenêtre historique).
    static func replaceChrome(conversationId: String, chrome: [String: MessageChromeMeta]) {
        if chrome.isEmpty {
            chromeMemory.removeValue(forKey: conversationId)
        } else {
            chromeMemory[conversationId] = chrome
        }
        persistChromeToDisk(conversationId)
    }

    static func setChrome(
        _ meta: MessageChromeMeta,
        conversationId: String,
        messageId: String
    ) {
        var map = chromeMemory[conversationId] ?? [:]
        map[messageId] = meta
        chromeMemory[conversationId] = map
        persistChromeToDisk(conversationId)
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
        var map = chrome(for: conversationId)
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
            persistChromeToDisk(conversationId)
        }
        return map
    }

    /// Rattache les filesFound orphelins (id local `asst-*` après restart) aux messages assistant du fil.
    static func reattachOrphanFilesFound(
        conversationId: String,
        messages: [MessageDTO]
    ) -> [String: MessageChromeMeta] {
        var map = chrome(for: conversationId)
        let liveIds = Set(messages.map(\.id))
        let orphans = map.filter { id, meta in
            !liveIds.contains(id) && !meta.filesFound.isEmpty
        }
        if !orphans.isEmpty {
            let assistants = messages.filter { $0.role == "assistant" }
            for (orphanId, meta) in orphans {
                let matched = assistants.last(where: { msg in
                    meta.filesFound.contains { file in
                        msg.content.localizedCaseInsensitiveContains(file.filename)
                            || msg.content.localizedCaseInsensitiveContains(file.id)
                    }
                }) ?? assistants.last
                guard let target = matched else { continue }
                var merged = map[target.id] ?? MessageChromeMeta()
                var seen = Set(merged.filesFound.map(\.id))
                for file in meta.filesFound where seen.insert(file.id).inserted {
                    merged.filesFound.append(file)
                }
                if !meta.savedMemories.isEmpty {
                    merged.savedMemories = mergeSavedMemories(merged.savedMemories, meta.savedMemories)
                }
                map[target.id] = merged
                map.removeValue(forKey: orphanId)
            }
            chromeMemory[conversationId] = map
            persistChromeToDisk(conversationId)
        }

        // Récupération contenu : narration « ID du fichier / Nom du fichier » sans chrome SSE.
        var changed = false
        for msg in messages where msg.role == "assistant" {
            var meta = map[msg.id] ?? MessageChromeMeta()
            guard meta.filesFound.isEmpty else { continue }
            let hints = extractFilesFoundHints(from: msg.content)
            guard !hints.isEmpty else { continue }
            meta.filesFound = hints
            map[msg.id] = meta
            changed = true
        }
        if changed {
            chromeMemory[conversationId] = map
            persistChromeToDisk(conversationId)
        }
        return map
    }

    /// Extrait des indices fichiers depuis le texte assistant (labels FR/EN, pas de domaine métier).
    /// Tolère le markdown gras du type `**ID du fichier :** abc123` (les `*` entre label et `:`).
    static func extractFilesFoundHints(from content: String) -> [FilesFoundFileDTO] {
        let raw = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.count >= 12 else { return [] }

        // Normalise : retire emphase markdown / NBSP qui cassent `fichier :` → `fichier :**`.
        let text = raw
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(
                of: #"\*+|_+"#,
                with: "",
                options: .regularExpression
            )

        // Marqueurs optionnels entre label et valeur (au cas où du markdown reste).
        let glue = #"\s*[*_~`]*\s*[:：]\s*[*_~`]*\s*"#
        let idPattern = #"(?i)(?:id\s*(?:du\s*)?fichier|file\s*id|fileid)"# + glue + #"([A-Za-z0-9_-]{6,})"#
        let namePattern = #"(?i)(?:nom\s*(?:du\s*)?fichier|file\s*name|filename)"# + glue + #"(.+)$"#

        var ids: [String] = []
        if let re = try? NSRegularExpression(pattern: idPattern) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in re.matches(in: text, range: range) {
                guard match.numberOfRanges >= 2,
                      let r = Range(match.range(at: 1), in: text) else { continue }
                let id = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !id.isEmpty { ids.append(id) }
            }
        }

        var names: [String] = []
        if let re = try? NSRegularExpression(pattern: namePattern, options: [.anchorsMatchLines]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in re.matches(in: text, range: range) {
                guard match.numberOfRanges >= 2,
                      let r = Range(match.range(at: 1), in: text) else { continue }
                var name = String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Coupe un éventuel suffixe markdown / ponctuation collée.
                if let cut = name.firstIndex(where: { $0 == "\n" || $0 == "*" || $0 == "`" }) {
                    name = String(name[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                name = name.trimmingCharacters(in: CharacterSet(charactersIn: "*_`"))
                if !name.isEmpty { names.append(name) }
            }
        }

        guard !ids.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [FilesFoundFileDTO] = []
        for (idx, id) in ids.enumerated() {
            guard seen.insert(id).inserted else { continue }
            let filename: String = {
                if idx < names.count { return names[idx] }
                if names.count == 1 { return names[0] }
                return "fichier"
            }()
            let ext = (filename as NSString).pathExtension
            out.append(
                FilesFoundFileDTO(
                    id: id,
                    filename: filename,
                    relativePath: nil,
                    rootId: nil,
                    sizeBytes: nil,
                    mtimeMs: nil,
                    extensionHint: ext.isEmpty ? nil : ext.lowercased()
                )
            )
        }
        return out
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
        /// Carte masquée (croix) — récupérable, pas annulée serveur.
        var collapsed: Bool

        enum CodingKeys: String, CodingKey {
            case draftId, text, to, subject, status, sent, inConversation, collapsed
        }

        init(
            draftId: String?,
            text: String,
            to: String,
            subject: String,
            status: String,
            sent: Bool,
            inConversation: Bool,
            collapsed: Bool = false
        ) {
            self.draftId = draftId
            self.text = text
            self.to = to
            self.subject = subject
            self.status = status
            self.sent = sent
            self.inConversation = inConversation
            self.collapsed = collapsed
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            draftId = try c.decodeIfPresent(String.self, forKey: .draftId)
            text = try c.decode(String.self, forKey: .text)
            to = try c.decode(String.self, forKey: .to)
            subject = try c.decode(String.self, forKey: .subject)
            status = try c.decode(String.self, forKey: .status)
            sent = try c.decode(Bool.self, forKey: .sent)
            inConversation = try c.decode(Bool.self, forKey: .inConversation)
            collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        }
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
