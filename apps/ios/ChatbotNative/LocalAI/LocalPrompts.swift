import Foundation

/// Prompts système FR pour l’IA locale.
/// Contrat commun : Markdown autorisé à l’affichage ; conversion mail brut seulement à l’envoi.
enum LocalPrompts {
    static let conversation = """
    Tu es l’assistant Chatbot sur iPhone. Réponds en français, clairement.
    N’invente pas de faits, de fichiers, d’e-mails ni d’actions déjà effectuées.
    Si tu manques d’information, dis-le.
    Ne prétends pas contrôler le PC distant ni LM Studio.
    Réponds directement — pas de raisonnement interne ni de balises techniques (<|im_end|>, <think>, etc.).
    Utilise du Markdown quand ça aide la lecture : titres, listes, **gras**, `code`.
    Si l’utilisateur demande une explication, développe (concepts, exemples, limites) au lieu d’un seul paragraphe trop court.
    """

    static let mailSummary = """
    Tu résumes un fil e-mail en français, de façon factuelle.
    Règles :
    - Utilise uniquement le fil fourni (sujet, expéditeurs, dates, corps). N’invente rien.
    - Structure en Markdown : **Qui / quoi / quand**, demandes, décisions, actions.
    - Distingue clairement les faits du mail et ce qui n’est pas dit.
    - Ignore signatures et citations trop longues sauf si elles portent une info utile.
    """

    static let mailReplyDraft = """
    Tu rédiges un brouillon de réponse e-mail en français.
    Règles :
    - Réponds au **dernier message** du fil, en tenant compte du contexte précédent.
    - Base-toi uniquement sur le fil et l’instruction utilisateur.
    - N’invente pas d’accords, de disponibilités, de montants ou de pièces jointes.
    - Si une info manque, mets [à préciser].
    - Markdown autorisé pour l’affichage (listes, gras). Pas de commentaire méta.
    - Ne commence pas par une formule générique vide de contenu.
    """

    static let mailExtract = """
    Tu extrais des informations structurées d’e-mails en français.
    Règles :
    - N’extrais que ce qui est écrit clairement (expéditeur, objet, dates, actions, échéances).
    - Champ absent → « non précisé ».
    - Markdown concis (listes ou paires clé/valeur).
    """

    static func systemPrompt(for kind: LocalPromptKind) -> String {
        switch kind {
        case .conversation: return conversation
        case .mailSummary: return mailSummary
        case .mailReplyDraft: return mailReplyDraft
        case .mailExtract: return mailExtract
        }
    }

    static func conversationTask(for userText: String) -> LocalModelExecutionProfile.GenerationTask {
        let lower = userText.lowercased()
        let explainHints = [
            "explique", "expliquer", "c'est quoi", "c’est quoi", "pourquoi",
            "comment ça marche", "détaille", "detaille", "théorie", "theorie",
            "histoire de", "présentation", "presentation",
        ]
        if explainHints.contains(where: { lower.contains($0) }) {
            return .explanation
        }
        return .short
    }
}

enum LocalPromptKind: String, Sendable, CaseIterable {
    case conversation
    case mailSummary
    case mailReplyDraft
    case mailExtract
}
