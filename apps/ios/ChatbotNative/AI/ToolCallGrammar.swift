import Foundation

/// Grammaires GBNF pour les sorties structurées.
///
/// Sans grammaire, on demande à un modèle 2B de produire du JSON par simple
/// consigne, puis on rattrape ses erreurs en cherchant la première `{` et la
/// dernière `}` du texte. Chaque échec de parsing coûte un tour d'agent complet
/// et se termine souvent en « Parse invalide, reformuler ».
///
/// La grammaire supprime la classe entière de pannes : les tokens qui
/// violeraient la structure sont masqués avant l'échantillonnage, donc la sortie
/// est valide par construction. C'est le levier de fiabilité le plus direct pour
/// un petit modèle.
enum ToolCallGrammar {
    /// Fragments JSON communs.
    ///
    /// `char` exclut `"` et `\` et n'autorise que les échappements légaux :
    /// une chaîne produite est toujours désérialisable par `JSONSerialization`.
    private static let jsonPrimitives = """
    ws        ::= [ \\t\\n]*
    string    ::= "\\"" char* "\\""
    char      ::= [^"\\\\\\x7F\\x00-\\x1F] | "\\\\" escape
    escape    ::= ["\\\\/bfnrt] | "u" [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F] [0-9a-fA-F]
    """

    /// Contraint la réponse à `{"type":"tool",...}` ou `{"type":"final",...}`.
    ///
    /// `action` est une alternance littérale des outils réellement enregistrés :
    /// le modèle ne peut plus inventer `search_web` quand l'outil s'appelle
    /// `web_search`, ni halluciner un outil absent du registre.
    static func agentStep(toolNames: [String]) -> String? {
        let names = toolNames
            .filter { !$0.isEmpty }
            .sorted()
        guard !names.isEmpty else { return nil }
        let actionAlternatives = names
            .map { "\"\\\"\($0)\\\"\"" }
            .joined(separator: " | ")

        return """
        root      ::= toolCall | finalAnswer

        toolCall  ::= "{" ws "\\"type\\"" ws ":" ws "\\"tool\\"" ws "," ws \
        "\\"action\\"" ws ":" ws action ws "," ws \
        "\\"arguments\\"" ws ":" ws argObject ws "}"

        finalAnswer ::= "{" ws "\\"type\\"" ws ":" ws "\\"final\\"" ws "," ws \
        "\\"content\\"" ws ":" ws string ws "}"

        action    ::= \(actionAlternatives)

        argObject ::= "{" ws "}" | "{" ws argPair (ws "," ws argPair)* ws "}"
        argPair   ::= string ws ":" ws string

        \(jsonPrimitives)
        """
    }

    /// Plan d'agent : `{"steps":[{"id":"s1","title":"..."}]}`.
    ///
    /// Le tableau peut être vide — c'est le signal « prêt à répondre » attendu
    /// par `revisedPlan`.
    static let agentPlan = """
    root      ::= "{" ws "\\"steps\\"" ws ":" ws stepArray ws "}"
    stepArray ::= "[" ws "]" | "[" ws step (ws "," ws step)* ws "]"
    step      ::= "{" ws "\\"id\\"" ws ":" ws string ws "," ws "\\"title\\"" ws ":" ws string ws "}"

    \(jsonPrimitives)
    """

    /// Faits extraits d'un tour de conversation, pour la mémoire long terme.
    static let memoryFacts = """
    root      ::= "{" ws "\\"facts\\"" ws ":" ws factArray ws "}"
    factArray ::= "[" ws "]" | "[" ws string (ws "," ws string)* ws "]"

    \(jsonPrimitives)
    """
}
