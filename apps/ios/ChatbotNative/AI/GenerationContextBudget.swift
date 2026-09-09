import Foundation

/// Budget réel llama : `promptTokens + reservedOutput <= n_ctx`.
/// `n_ctx` n’est **pas** un budget de prompt ; une partie est réservée à la génération.
///
/// L'arbitrage lui-même appartient désormais à `LocalPromptFitter`, qui compte
/// de vrais tokens du modèle chargé. Ne restent ici que les constantes et les
/// replis partagés : la version précédente exposait aussi un budget dérivé du
/// profil et une réduction d'historique par tentative, tous deux court-circuités
/// par le fitter et donc trompeurs à laisser en place.
enum GenerationContextBudget {
    /// Marge fixe conservée sous `n_ctx`.
    ///
    /// 8 tokens ne suffisaient pas : l'en-tête assistant avec préremplissage
    /// `<think>\n\n</think>\n\n` en consomme déjà 6, et le décalage entre le
    /// comptage du prompt et sa retokenisation dans le moteur atteint quelques
    /// tokens. Franchir `n_ctx` fait échouer le decode, pas seulement tronquer.
    static let safetyTokens = 32

    /// Repli **uniquement** quand le tokenizer llama est indisponible (modèle non
    /// chargé). Le compte en octets UTF-8 / 3 surestime le français accentué —
    /// c'est voulu : surestimer tronque un peu trop, sous-estimer casse le decode.
    static func estimateTokens(_ text: String) -> Int {
        max(1, (text.utf8.count + 2) / 3)
    }

    static func clip(_ text: String, maxChars: Int) -> String {
        guard maxChars > 0 else { return "" }
        if text.count <= maxChars { return text }
        return String(text.prefix(maxChars))
    }
}

enum GenerationRunPhase: String, Equatable, Sendable {
    case started
    case planning
    case searching
    case analyzing
    case generating
    case completed
    case failed
    case cancelled
}

/// Isolation d’une génération (sources / tools / stream ne fuient pas vers le tour suivant).
/// Les sources appartiennent au run, jamais au « dernier assistant » de la conversation.
struct GenerationRunState: Equatable, Sendable {
    var id: String
    var messageId: String?
    var startedAt: Date
    var workflow: String
    var phase: GenerationRunPhase
    var query: String?
    var discoveredSources: [SearchSourceDTO]
    var finalSources: [SearchSourceDTO]
    var mailContext: Bool
    var webContext: Bool
    var mailThreadId: String?

    /// Compat lecture : finales si le run est clos, sinon découvertes.
    var sources: [SearchSourceDTO] {
        get { finalSources.isEmpty ? discoveredSources : finalSources }
        set { discoveredSources = newValue }
    }

    static func start(workflow: String = "chat") -> GenerationRunState {
        GenerationRunState(
            id: UUID().uuidString,
            messageId: nil,
            startedAt: Date(),
            workflow: workflow,
            phase: .started,
            query: nil,
            discoveredSources: [],
            finalSources: [],
            mailContext: false,
            webContext: false,
            mailThreadId: nil
        )
    }

    func log(_ event: String, extra: [String: String] = [:]) {
        var fields = extra
        fields["id"] = id
        if fields["workflow"] == nil { fields["workflow"] = workflow }
        WorkflowTrace.log("run:\(event)", fields)
    }
}
