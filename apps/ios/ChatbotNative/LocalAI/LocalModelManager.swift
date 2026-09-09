import Foundation
import Combine
import Metal

/// Gestion téléchargement / installation / chargement du GGUF local.
/// Ne touche **jamais** aux modèles LM Studio du PC.
@MainActor
final class LocalModelManager: ObservableObject {
    static let shared = LocalModelManager()

    @Published private(set) var state: LocalModelInstallState = .notInstalled
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastError: String?
    @Published private(set) var isMetalAvailable: Bool = false
    @Published private(set) var activeModelId: String = LocalModelDescriptor.primary.id
    @Published private(set) var installedBytes: Int64 = 0

    private var downloadTask: URLSessionDownloadTask?
    private var downloadDelegate: DownloadDelegate?
    private var session: URLSession?
    private var installGeneration: UInt64 = 0

    private let engine = LocalInferenceEngine.shared
    private let fileManager = FileManager.default

    var activeDescriptor: LocalModelDescriptor {
        LocalModelDescriptor.descriptor(id: activeModelId) ?? .primary
    }

    var modelsDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Models", isDirectory: true)
        if !fileManager.fileExists(atPath: fileSystemPath(dir)) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutable = dir
            try? mutable.setResourceValues(values)
        }
        return dir
    }

    var modelFileURL: URL {
        modelsDirectory.appendingPathComponent(activeDescriptor.filename)
    }

    /// Chemin filesystem stable (évite les surprises `%20` / encoding).
    var modelFilePath: String { fileSystemPath(modelFileURL) }

    private var partialDownloadURL: URL {
        modelsDirectory.appendingPathComponent(activeDescriptor.filename + ".download")
    }

    var actualFileExists: Bool {
        fileManager.fileExists(atPath: modelFilePath)
    }

    var actualFileIsReadable: Bool {
        fileManager.isReadableFile(atPath: modelFilePath)
    }

    var actualFileSize: Int64 {
        (try? fileManager.attributesOfItem(atPath: modelFilePath)[.size] as? Int64) ?? 0
    }

    /// Installé = fichier GGUF réellement présent, à la bonne taille et lisible.
    var isInstalled: Bool {
        guard actualFileExists,
              actualFileSize > 0,
              validateSize(actualFileSize, expected: activeDescriptor.expectedBytes),
              isGGUFMagic(at: modelFileURL) else { return false }
        return true
    }

    var isReady: Bool {
        if case .ready = state { return true }
        if case .generating = state { return true }
        return false
    }

    init() {
        refreshMetalAvailability()
        refreshInstalledState()
    }

    func refreshMetalAvailability() {
#if targetEnvironment(simulator)
        isMetalAvailable = false
#else
        isMetalAvailable = MTLCreateSystemDefaultDevice() != nil
#endif
    }

    func refreshInstalledState() {
        let path = modelFilePath
        recordStorageAudit("refresh")
        guard fileManager.fileExists(atPath: path) else {
            if case .downloading = state { return }
            if case .verifying = state { return }
            if case .loading = state { return }
            if case .ready = state { return }
            if case .generating = state { return }
            state = .notInstalled
            installedBytes = 0
            progress = 0
            return
        }
        let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        installedBytes = size
        // Ne jamais supprimer silencieusement un gros téléchargement au refresh :
        // signaler l’erreur et laisser l’utilisateur réinstaller / supprimer.
        if !validateSize(size, expected: activeDescriptor.expectedBytes) || !isGGUFMagic(at: modelFileURL) {
            switch state {
            case .ready, .generating, .loading, .unloading, .downloading, .verifying:
                break
            default:
                state = .installed
            }
            lastError = "Fichier modèle invalide ou incomplet (\(byteLabel(size))). Supprimez puis réinstallez."
            return
        }
        switch state {
        case .ready, .generating, .loading, .unloading, .downloading, .verifying:
            break
        default:
            state = .installed
            if lastError?.contains("invalide") == true || lastError?.contains("introuvable") == true {
                lastError = nil
            }
        }
    }

    // MARK: - Install / Download

    func install(model: LocalModelDescriptor = .primary) async {
        guard var remoteURL = model.downloadURL else {
            lastError = "Ce modèle n’est pas encore téléchargeable."
            state = .failed(lastError!)
            return
        }
        if case .downloading = state { return }
        if case .verifying = state { return }

        // Force le téléchargement binaire HF (évite pages HTML / pointeurs LFS).
        if var comps = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false) {
            var items = comps.queryItems ?? []
            if !items.contains(where: { $0.name == "download" }) {
                items.append(URLQueryItem(name: "download", value: "true"))
            }
            comps.queryItems = items
            if let u = comps.url { remoteURL = u }
        }

        activeModelId = model.id
        _ = modelsDirectory
        installGeneration &+= 1
        let generation = installGeneration
        lastError = nil
        progress = 0
        state = .downloading(progress: 0)

        do {
            try await download(from: remoteURL, model: model, generation: generation)
            guard generation == installGeneration else { return }
            state = .verifying
            try validateInstalledFile(model: model)
            guard generation == installGeneration else { return }
            let size = (try? fileManager.attributesOfItem(atPath: modelFilePath)[.size] as? Int64) ?? model.expectedBytes
            installedBytes = size
            progress = 1
            state = .installed
            lastError = nil
        } catch is CancellationError {
            guard generation == installGeneration else { return }
            state = fileManager.fileExists(atPath: modelFilePath) ? .installed : .notInstalled
        } catch {
            guard generation == installGeneration else { return }
            lastError = error.localizedDescription
            state = .failed(error.localizedDescription)
            if fileManager.fileExists(atPath: modelFilePath) {
                let size = (try? fileManager.attributesOfItem(atPath: modelFilePath)[.size] as? Int64) ?? 0
                if !validateSize(size, expected: model.expectedBytes) || !isGGUFMagic(at: modelFileURL) {
                    try? fileManager.removeItem(at: modelFileURL)
                }
            }
        }
    }

    func cancelDownload() {
        installGeneration &+= 1
        downloadTask?.cancel()
        downloadTask = nil
        session?.invalidateAndCancel()
        session = nil
        downloadDelegate = nil
        if case .downloading = state {
            state = fileManager.fileExists(atPath: modelFilePath) ? .installed : .notInstalled
            progress = 0
        }
    }

    func deleteModel() async {
        cancelDownload()
        await unload()
        try? fileManager.removeItem(at: modelFileURL)
        try? fileManager.removeItem(at: partialDownloadURL)
        installedBytes = 0
        progress = 0
        lastError = nil
        state = .notInstalled
    }

    // MARK: - Engine

    func loadIntoEngine() async {
        refreshInstalledState()
        let path = modelFilePath
        guard fileManager.fileExists(atPath: path) else {
            lastError = missingFileDiagnostic()
            state = .notInstalled
            installedBytes = 0
            return
        }
        guard isGGUFMagic(at: modelFileURL) else {
            lastError = "Fichier présent mais ce n’est pas un GGUF valide. Supprimez puis réinstallez."
            state = .installed
            return
        }
        guard LocalInferenceEngine.isLlamaRuntimeAvailable else {
            lastError = LocalInferenceError.notAvailable.localizedDescription
            state = .installed
            return
        }

        state = .loading
        lastError = nil
        do {
            try await engine.load(path: path)
            state = .ready
        } catch {
            lastError = error.localizedDescription
            // Garder « installé » si le fichier est toujours là — ne pas faire croire qu’il faut retélécharger.
            state = fileManager.fileExists(atPath: path) ? .installed : .notInstalled
        }
    }

    func unload() async {
        state = .unloading
        await engine.cancel()
        await engine.unload()
        state = fileManager.fileExists(atPath: modelFilePath) ? .installed : .notInstalled
    }

    func markGenerating(_ active: Bool) {
        if active {
            if state == .ready { state = .generating }
        } else if state == .generating {
            state = .ready
        }
    }

    // MARK: - Private download

    private func download(from remoteURL: URL, model: LocalModelDescriptor, generation: UInt64) async throws {
        let destination = modelFileURL
        let partial = partialDownloadURL

        if fileManager.fileExists(atPath: fileSystemPath(destination)) {
            let size = (try? fileManager.attributesOfItem(atPath: fileSystemPath(destination))[.size] as? Int64) ?? 0
            if validateSize(size, expected: model.expectedBytes), isGGUFMagic(at: destination) {
                return
            }
            try? fileManager.removeItem(at: destination)
        }

        var existingBytes: Int64 = 0
        if fileManager.fileExists(atPath: fileSystemPath(partial)) {
            existingBytes = (try? fileManager.attributesOfItem(atPath: fileSystemPath(partial))[.size] as? Int64) ?? 0
            // Partiel minuscule / HTML / 404 → repartir de zéro.
            if existingBytes > 0, existingBytes < 1_000_000, model.expectedBytes > 100_000_000 {
                try? fileManager.removeItem(at: partial)
                existingBytes = 0
            }
        }

        do {
            try await performDownload(
                remoteURL: remoteURL,
                model: model,
                generation: generation,
                existingBytes: existingBytes,
                partial: partial,
                destination: destination
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if existingBytes > 0 {
                try? fileManager.removeItem(at: partial)
                try await performDownload(
                    remoteURL: remoteURL,
                    model: model,
                    generation: generation,
                    existingBytes: 0,
                    partial: partial,
                    destination: destination
                )
            } else {
                throw error
            }
        }
    }

    private func performDownload(
        remoteURL: URL,
        model: LocalModelDescriptor,
        generation: UInt64,
        existingBytes: Int64,
        partial: URL,
        destination: URL
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = DownloadDelegate(
                partialURL: partial,
                destinationURL: destination,
                expectedBytes: model.expectedBytes,
                existingBytes: existingBytes,
                onProgress: { [weak self] fraction in
                    Task { @MainActor in
                        guard let self, generation == self.installGeneration else { return }
                        self.progress = fraction
                        self.state = .downloading(progress: fraction)
                    }
                },
                onComplete: { [weak self] result in
                    Task { @MainActor in
                        self?.downloadTask = nil
                        self?.session = nil
                        self?.downloadDelegate = nil
                        continuation.resume(with: result)
                    }
                }
            )
            self.downloadDelegate = delegate

            let config = URLSessionConfiguration.default
            config.allowsCellularAccess = true
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 60 * 60 * 2
            let urlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            self.session = urlSession

            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 60 * 60 * 2
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
            if existingBytes > 0 {
                request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
            }
            let task = urlSession.downloadTask(with: request)
            self.downloadTask = task
            task.resume()
        }
    }

    private func validateInstalledFile(model: LocalModelDescriptor) throws {
        let path = modelFilePath
        guard fileManager.fileExists(atPath: path) else {
            throw LocalInferenceError.modelMissing
        }
        let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        guard validateSize(size, expected: model.expectedBytes) else {
            try? fileManager.removeItem(at: modelFileURL)
            let actualMB = Double(size) / 1_048_576.0
            let expectedMB = Double(model.expectedBytes) / 1_048_576.0
            throw NSError(
                domain: "LocalModelManager",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        String(
                            format: "Taille du modèle hors tolérance (±5 %%): %.0f Mo reçus, %.0f Mo attendus.",
                            actualMB,
                            expectedMB
                        )
                ]
            )
        }
        guard isGGUFMagic(at: modelFileURL) else {
            try? fileManager.removeItem(at: modelFileURL)
            throw NSError(
                domain: "LocalModelManager",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Le fichier téléchargé n’est pas un GGUF (en-tête invalide). Réessaie l’installation."
                ]
            )
        }
        installedBytes = size
        recordStorageAudit("validation après téléchargement/move")
    }

    private func validateSize(_ actual: Int64, expected: Int64) -> Bool {
        guard expected > 0, actual > 0 else { return false }
        let tolerance = Double(expected) * 0.05
        return abs(Double(actual - expected)) <= tolerance
    }

    private func isGGUFMagic(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        return data == Data("GGUF".utf8)
    }

    private func fileSystemPath(_ url: URL) -> String {
        url.path(percentEncoded: false)
    }

    private func byteLabel(_ bytes: Int64) -> String {
        String(format: "%.0f Mo", Double(bytes) / 1_048_576.0)
    }

    private func missingFileDiagnostic() -> String {
        let dir = modelsDirectory
        let contents = (try? fileManager.contentsOfDirectory(atPath: fileSystemPath(dir))) ?? []
        if contents.isEmpty {
            return "Modèle GGUF introuvable dans Models/. Relancez Installer."
        }
        return "Modèle GGUF introuvable (\(activeDescriptor.filename)). Dossier Models: \(contents.joined(separator: ", ")). Relancez Installer."
    }

    /// Trace de cycle de vie sans contenu de fichier ni donnée utilisateur.
    private func recordStorageAudit(_ event: String) {
        let path = modelFilePath
        let partial = partialDownloadURL
        let size = (try? fileManager.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        let magic = fileManager.fileExists(atPath: path) && isGGUFMagic(at: modelFileURL)
        print(
            "[local-ai:storage] event=\(event), final.exists=\(fileManager.fileExists(atPath: path)), " +
            "final.readable=\(fileManager.isReadableFile(atPath: path)), final.size=\(size), " +
            "final.ggufMagic=\(magic), partial.exists=\(fileManager.fileExists(atPath: fileSystemPath(partial))), " +
            "final.path=\(path)"
        )
    }
}

// MARK: - URLSession download delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let partialURL: URL
    private let destinationURL: URL
    private let expectedBytes: Int64
    private let existingBytes: Int64
    private let onProgress: @Sendable (Double) -> Void
    private let onComplete: @Sendable (Result<Void, Error>) -> Void
    private var finished = false
    private let lock = NSLock()

    init(
        partialURL: URL,
        destinationURL: URL,
        expectedBytes: Int64,
        existingBytes: Int64,
        onProgress: @escaping @Sendable (Double) -> Void,
        onComplete: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.partialURL = partialURL
        self.destinationURL = destinationURL
        self.expectedBytes = expectedBytes
        self.existingBytes = existingBytes
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let written = existingBytes + totalBytesWritten
        let total: Int64
        if totalBytesExpectedToWrite > 0 {
            total = existingBytes + totalBytesExpectedToWrite
        } else if expectedBytes > 0 {
            total = expectedBytes
        } else {
            total = max(written, 1)
        }
        let fraction = min(1, Double(written) / Double(total))
        onProgress(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let fm = FileManager.default
            let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
            guard (200...299).contains(status) else {
                try? fm.removeItem(at: location)
                throw NSError(
                    domain: "LocalModelManager",
                    code: status,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Téléchargement du modèle refusé (HTTP \(status)). Vérifiez l’URL Hugging Face."
                    ]
                )
            }
            let shouldAppend = existingBytes > 0 && status == 206 && fm.fileExists(atPath: partialURL.path(percentEncoded: false))

            if shouldAppend {
                try Self.appendFile(from: location, onto: partialURL)
                try? fm.removeItem(at: location)
            } else {
                if fm.fileExists(atPath: partialURL.path(percentEncoded: false)) {
                    try fm.removeItem(at: partialURL)
                }
                try Self.moveOrCopy(location, to: partialURL)
            }

            if fm.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
                try fm.removeItem(at: destinationURL)
            }
            try Self.moveOrCopy(partialURL, to: destinationURL)
            let destinationPath = destinationURL.path(percentEncoded: false)
            let destinationExists = fm.fileExists(atPath: destinationPath)
            let destinationSize = (try? fm.attributesOfItem(atPath: destinationPath)[.size] as? Int64) ?? 0
            let partialExists = fm.fileExists(atPath: partialURL.path(percentEncoded: false))
            print(
                "[local-ai:download-move] partial.exists=\(partialExists), final.exists=\(destinationExists), " +
                "final.size=\(destinationSize), final.path=\(destinationPath)"
            )
            guard destinationExists, destinationSize > 0 else {
                throw NSError(
                    domain: "LocalModelManager",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Move GGUF terminé sans fichier final lisible."]
                )
            }
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
            finish(.failure(CancellationError()))
            return
        }
        if let response = task.response as? HTTPURLResponse, response.statusCode == 416 {
            try? FileManager.default.removeItem(at: partialURL)
        }
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        onComplete(result)
    }

    private static func moveOrCopy(_ from: URL, to: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: to.path(percentEncoded: false)) {
            try fm.removeItem(at: to)
        }
        do {
            try fm.moveItem(at: from, to: to)
        } catch {
            try fm.copyItem(at: from, to: to)
            try? fm.removeItem(at: from)
        }
    }

    /// Append sans charger le chunk entier en RAM (évite jetsam sur reprise Range).
    private static func appendFile(from source: URL, onto destination: URL) throws {
        let out = try FileHandle(forWritingTo: destination)
        defer { try? out.close() }
        try out.seekToEnd()
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let chunkSize = 1024 * 1024
        while true {
            let chunk = try input.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            try out.write(contentsOf: chunk)
        }
    }
}
