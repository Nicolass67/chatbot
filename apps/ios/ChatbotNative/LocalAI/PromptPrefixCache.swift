import Foundation

/// Cache disque du KV d'un préfixe de prompt stable.
///
/// À quoi ça sert exactement : la réutilisation du préfixe en mémoire couvre
/// déjà tous les tours d'une même session. Il reste un cas non couvert, le
/// **premier** message après un lancement ou un rechargement du modèle : le
/// prompt système doit être préfillé intégralement, soit environ 450 tokens.
///
/// Ce cache ne stocke que la partie réellement invariante du prompt système.
/// Le bloc horloge (qui change chaque jour) et les faits mémorisés (qui
/// changent à chaque nouveau fait) en sont exclus : les inclure invaliderait
/// le cache en permanence.
///
/// Sécurité : l'état KV dépend des paramètres exacts du contexte. Une empreinte
/// couvre modèle, `n_ctx`, type de KV et Flash Attention. Au moindre doute, on
/// ignore le cache — un préfill complet est lent, un état KV incohérent produit
/// du texte sans rapport avec le prompt.
enum PromptPrefixCache {
    /// Empreinte d'invalidation. Tout ce qui change la disposition du KV doit y figurer.
    struct Signature: Equatable, Codable, Sendable {
        var modelId: String
        var nCtx: UInt32
        var kvTypeK: String
        var kvTypeV: String
        var flashAttention: String
        var promptHash: String

        var fileName: String {
            // Le hash du prompt suffit à distinguer les entrées ; le reste est
            // vérifié à la lecture du fichier de métadonnées.
            "prefix-\(promptHash).kv"
        }

        var metadataFileName: String {
            "prefix-\(promptHash).json"
        }
    }

    /// Un état KV de 450 tokens en q8_0 pèse déjà quelques dizaines de Mo.
    /// Au-delà, la lecture disque coûte plus que le préfill qu'elle évite.
    private static let maxStateBytes: Int64 = 96 * 1_048_576
    private static let minCachedTokens = 96

    static func signature(
        modelId: String,
        config: LlamaInferenceConfig,
        prompt: String
    ) -> Signature {
        Signature(
            modelId: modelId,
            nCtx: config.nCtx,
            kvTypeK: config.kvCacheTypeK.rawValue,
            kvTypeV: config.kvCacheTypeV.rawValue,
            flashAttention: config.effectiveFlashAttention.rawValue,
            promptHash: stableHash(prompt)
        )
    }

    static func directory() -> URL? {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = caches.appendingPathComponent("ChatbotPromptCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Chemin d'un état valide et compatible, ou `nil`.
    static func existingState(for signature: Signature) -> URL? {
        guard let directory = directory() else { return nil }
        let metadataURL = directory.appendingPathComponent(signature.metadataFileName)
        let stateURL = directory.appendingPathComponent(signature.fileName)

        guard let data = try? Data(contentsOf: metadataURL),
              let stored = try? JSONDecoder().decode(Signature.self, from: data),
              stored == signature,
              FileManager.default.fileExists(atPath: stateURL.path(percentEncoded: false)) else {
            return nil
        }
        let size = (try? FileManager.default.attributesOfItem(
            atPath: stateURL.path(percentEncoded: false)
        )[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0, size <= maxStateBytes else {
            discard(signature: signature)
            return nil
        }
        return stateURL
    }

    /// Destination d'écriture, après purge des entrées devenues incompatibles.
    static func stateURLForWriting(signature: Signature, tokenCount: Int) -> URL? {
        guard tokenCount >= minCachedTokens, let directory = directory() else { return nil }
        purgeStaleEntries(keeping: signature)
        return directory.appendingPathComponent(signature.fileName)
    }

    static func writeMetadata(_ signature: Signature) {
        guard let directory = directory(),
              let data = try? JSONEncoder().encode(signature) else { return }
        try? data.write(
            to: directory.appendingPathComponent(signature.metadataFileName),
            options: .atomic
        )
    }

    static func discard(signature: Signature) {
        guard let directory = directory() else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(signature.fileName))
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(signature.metadataFileName))
    }

    /// Une seule entrée conservée : le prompt système change rarement, et un
    /// répertoire de caches qui grossit sans limite finit par être purgé par iOS
    /// au pire moment.
    private static func purgeStaleEntries(keeping signature: Signature) {
        guard let directory = directory() else { return }
        let keep = Set([signature.fileName, signature.metadataFileName])
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        for entry in entries where !keep.contains(entry.lastPathComponent) {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    /// FNV-1a 64 bits — stable entre lancements, contrairement à `Hasher`
    /// dont la graine est randomisée par processus.
    static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(hash, radix: 16)
    }
}
