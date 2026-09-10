import Foundation

/// Résumé roulant d'une conversation, persisté entre deux lancements.
struct ConversationRollingSummary: Codable, Equatable, Sendable {
    var conversationId: String
    /// Résumé en prose des messages déjà repliés.
    var summary: String
    /// Nombre de messages d'historique couverts par `summary`.
    var coveredMessageCount: Int
    var updatedAt: Date
}

/// Mémoire de conversation : résumé roulant produit par le modèle et extraction
/// des faits durables.
///
/// Le point clé est **quand** ce travail a lieu : après que la réponse a été
/// rendue, jamais avant. Résumer en amont d'un tour ajouterait plusieurs
/// secondes avant le premier token ; résumer en aval, le coût est invisible.
///
/// Le compresseur précédent appelait « résumé » une simple troncature : les six
/// derniers messages anciens coupés à 160 caractères. Ça préservait des débuts
/// de phrase, pas de l'information. Sur une conversation de trente tours, tout
/// ce qui avait été établi au début était perdu.
@MainActor
final class ConversationMemoryService {
    static let shared = ConversationMemoryService()

    private var summaries: [String: ConversationRollingSummary] = [:]
    private var inFlight: Set<String> = []
    private let storeURL: URL?
    /// Travail de fond en cours. Le moteur local est unique et sérialisé :
    /// s'il est en train de résumer, le prochain message de l'utilisateur
    /// attendrait derrière. La mémoire cède toujours la place au tour en cours.
    private var backgroundWork: Task<Void, Never>?

    /// Nombre de nouveaux messages repliés avant de relancer un résumé.
    /// Trop bas : on résume à chaque tour pour rien. Trop haut : le résumé
    /// retarde et le repli déterministe reste visible trop longtemps.
    private let regenerationThreshold = 6

    init() {
        storeURL = Self.makeStoreURL()
        summaries = Self.load(from: storeURL)
    }

    // MARK: Lecture (chemin critique, synchrone)

    func summary(for conversationId: String?) -> ConversationRollingSummary? {
        guard let conversationId, !conversationId.isEmpty else { return nil }
        return summaries[conversationId]
    }

    // MARK: Écriture (hors chemin critique)

    /// À appeler après qu'un tour est terminé et affiché.
    ///
    /// Détaché volontairement : une erreur ou une lenteur ici ne doit jamais
    /// remonter à l'utilisateur, le tour est déjà rendu.
    func ingestTurn(
        conversationId: String?,
        history: [LLMChatMessage],
        userText: String,
        assistantText: String,
        runtime: any AIRuntime
    ) {
        backgroundWork?.cancel()
        backgroundWork = Task { @MainActor in
            // Laisser le tour se terminer côté UI et l'utilisateur reprendre la
            // main : s'il enchaîne tout de suite, la mémoire est annulée avant
            // d'avoir occupé le moteur.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self.extractFacts(
                userText: userText,
                assistantText: assistantText,
                runtime: runtime
            )
            guard !Task.isCancelled else { return }
            await self.refreshSummaryIfNeeded(
                conversationId: conversationId,
                history: history,
                runtime: runtime
            )
        }
    }

    /// Rend le moteur au tour utilisateur qui démarre.
    func yieldEngine() {
        backgroundWork?.cancel()
        backgroundWork = nil
    }

    // MARK: Résumé roulant

    private func refreshSummaryIfNeeded(
        conversationId: String?,
        history: [LLMChatMessage],
        runtime: any AIRuntime
    ) async {
        guard let conversationId, !conversationId.isEmpty else { return }
        guard !inFlight.contains(conversationId) else { return }

        let profile = runtime.executionProfile
        let keepRecent = max(2, profile.historyMessageBudget)
        let foldableCount = max(0, history.count - keepRecent)
        let existing = summaries[conversationId]
        let covered = existing?.coveredMessageCount ?? 0
        guard foldableCount - covered >= regenerationThreshold else { return }

        let newlyFolded = Array(history[covered..<foldableCount])
        guard !newlyFolded.isEmpty else { return }

        inFlight.insert(conversationId)
        defer { inFlight.remove(conversationId) }

        let transcript = newlyFolded
            .map { message -> String in
                let role: String
                switch message.role {
                case .user: role = "Utilisateur"
                case .assistant: role = "Assistant"
                default: role = "Système"
                }
                return "\(role) : \(String(message.content.prefix(700)))"
            }
            .joined(separator: "\n")

        let previous = existing?.summary ?? ""
        let user = """
        RÉSUMÉ EXISTANT :
        \(previous.isEmpty ? "(aucun)" : previous)

        NOUVEAUX ÉCHANGES À INTÉGRER :
        \(transcript)
        """

        do {
            let raw = try await runtime.generateLocal(
                system: """
                Tu maintiens la mémoire d’une conversation. Produis un résumé unique, à jour, \
                qui remplace le résumé existant en y intégrant les nouveaux échanges.
                Conserve en priorité : ce que l’utilisateur a demandé, les décisions prises, \
                les préférences exprimées, les faits personnels, les contraintes, et ce qui reste en suspens.
                Supprime les politesses, les redites et les détails sans conséquence.
                Écris en français, en prose dense, 150 mots maximum. Pas de liste, pas de titre, pas de commentaire.
                """,
                messages: [LLMChatMessage(role: .user, content: user)],
                maxTokens: 320,
                options: LocalGenerationOptions(sampling: .factual, timeout: 90)
            )
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard cleaned.count >= 40 else { return }

            summaries[conversationId] = ConversationRollingSummary(
                conversationId: conversationId,
                summary: String(cleaned.prefix(1_400)),
                coveredMessageCount: foldableCount,
                updatedAt: Date()
            )
            persist()
            WorkflowTrace.log("memory", [
                "summary": "updated",
                "covered": "\(foldableCount)",
                "chars": "\(cleaned.count)",
            ])
        } catch {
            WorkflowTrace.log("memory", ["summary": "failed", "reason": error.localizedDescription])
        }
    }

    // MARK: Extraction de faits

    /// N'extrait que des faits **durables** sur l'utilisateur. La grammaire
    /// garantit un JSON exploitable, ce qui rend l'opération silencieuse et sûre.
    private func extractFacts(
        userText: String,
        assistantText: String,
        runtime: any AIRuntime
    ) async {
        let trimmed = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Un message très court ne porte pas de fait durable, et l'extraction
        // coûterait plus que ce qu'elle rapporte.
        guard trimmed.count >= 24 else { return }
        // Le filtre décisif : une question (« quelles sont les meilleures souris »)
        // ne contient aucun fait durable sur l'utilisateur. Sans ce garde-fou,
        // chaque tour payait une génération de plus pour un `{"facts":[]}`.
        guard Self.mayCarryDurableFact(trimmed) else {
            WorkflowTrace.log("memory", ["facts": "skipped"])
            return
        }

        let user = """
        MESSAGE UTILISATEUR :
        \(String(trimmed.prefix(1_200)))

        RÉPONSE ASSISTANT :
        \(String(assistantText.prefix(600)))
        """

        do {
            let raw = try await runtime.generateLocal(
                system: """
                Tu extrais les faits durables concernant l’utilisateur, à retenir pour les \
                conversations futures : prénom, métier, ville, matériel, préférences stables, \
                contraintes, projets en cours, personnes proches.
                N’extrais RIEN d’autre : pas de question posée, pas de sujet de discussion, \
                pas de fait général sur le monde, pas d’information temporaire.
                Chaque fait est une phrase courte et autonome, à la troisième personne \
                (« L’utilisateur … »), en français.
                Réponds {"facts":[]} s’il n’y a aucun fait durable — c’est le cas le plus fréquent.
                """,
                messages: [LLMChatMessage(role: .user, content: user)],
                maxTokens: 220,
                options: LocalGenerationOptions(
                    sampling: .structured,
                    grammar: ToolCallGrammar.memoryFacts,
                    timeout: 60
                )
            )
            let extracted = Self.parseFacts(raw)
            guard !extracted.isEmpty else { return }
            let inserted = LocalMemoryStore.shared.rememberAll(extracted)
            if inserted > 0 {
                WorkflowTrace.log("memory", [
                    "facts_extracted": "\(extracted.count)",
                    "facts_stored": "\(inserted)",
                ])
            }
        } catch {
            // Silencieux : l'extraction est un bonus, jamais un prérequis.
            WorkflowTrace.log("memory", ["facts": "failed"])
        }
    }

    /// Pré-filtre lexical : le message parle-t-il de l'utilisateur lui-même ?
    ///
    /// Volontairement large côté première personne (mieux vaut une extraction
    /// inutile qu'un fait manqué) mais strict sur les questions pures.
    static func mayCarryDurableFact(_ text: String) -> Bool {
        let lower = text.lowercased()
        let firstPerson = [
            "je ", "j'", "j’", "mon ", "ma ", "mes ", "moi ", "chez moi",
            "m'appelle", "m’appelle", "appelle-moi", "appelle moi",
            "retiens", "souviens-toi", "souviens toi", "note que", "rappelle-toi",
            "notre ", "nous avons", "on a ",
        ]
        guard firstPerson.contains(where: { lower.hasPrefix($0) || lower.contains(" " + $0) || lower.contains("\n" + $0) })
        else { return false }

        // « je cherche les meilleures souris » : première personne, mais c'est
        // une requête ponctuelle, pas un fait à garder.
        let transientRequest = [
            "je cherche", "je voudrais savoir", "je veux savoir", "je me demande",
            "peux-tu", "peux tu", "pourrais-tu", "donne-moi", "donne moi",
            "trouve-moi", "trouve moi", "explique", "résume", "resume", "traduis",
        ]
        if transientRequest.contains(where: { lower.contains($0) }),
           !lower.contains("retiens"), !lower.contains("souviens") {
            return false
        }
        return true
    }

    static func parseFacts(_ raw: String) -> [String] {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return []
        }
        text = String(text[start...end])
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["facts"] as? [String] else {
            return []
        }
        return list
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 8 && $0.count <= 300 }
            .prefix(5)
            .map { $0 }
    }

    // MARK: Persistance

    private static func makeStoreURL() -> URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = support.appendingPathComponent("ChatbotMemory", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("conversation-summaries.json")
    }

    private static func load(from url: URL?) -> [String: ConversationRollingSummary] {
        guard let url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: ConversationRollingSummary].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persist() {
        guard let storeURL, let data = try? JSONEncoder().encode(summaries) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
