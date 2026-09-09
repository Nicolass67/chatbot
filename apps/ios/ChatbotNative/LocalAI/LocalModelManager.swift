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
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    var modelFileURL: URL {
        modelsDirectory.appendingPathComponent(activeDescriptor.filename)
    }

    private var partialDownloadURL: URL {
        modelsDirectory.appendingPathComponent(activeDescriptor.filename + ".download")
    }

    var isInstalled: Bool {
        switch state {
        case .installed, .loading, .ready, .generating, .unloading:
            return true
        default:
            return false
        }
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
        let url = modelFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            // Partial alone ≠ installed.
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
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        installedBytes = size
        guard validateSize(size, expected: activeDescriptor.expectedBytes) else {
            // Fichier partiel / corrompu — ne pas marquer installé.
            try? fileManager.removeItem(at: url)
            state = .notInstalled
            installedBytes = 0
            lastError = "Fichier modèle incomplet — réinstallez."
            return
        }
        switch state {
        case .ready, .generating, .loading, .unloading, .downloading, .verifying:
            break
        default:
            state = .installed
        }
    }

    // MARK: - Install / Download

    func install(model: LocalModelDescriptor = .primary) async {
        guard let remoteURL = model.downloadURL else {
            lastError = "Ce modèle n’est pas encore téléchargeable."
            state = .failed(lastError!)
            return
        }
        if case .downloading = state { return }
        if case .verifying = state { return }

        activeModelId = model.id
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
            let size = (try? fileManager.attributesOfItem(atPath: modelFileURL.path)[.size] as? Int64) ?? model.expectedBytes
            installedBytes = size
            progress = 1
            state = .installed
        } catch is CancellationError {
            guard generation == installGeneration else { return }
            state = fileManager.fileExists(atPath: modelFileURL.path) ? .installed : .notInstalled
        } catch {
            guard generation == installGeneration else { return }
            lastError = error.localizedDescription
            state = .failed(error.localizedDescription)
            // Ne jamais laisser un partiel comme « installé ».
            if fileManager.fileExists(atPath: modelFileURL.path) {
                let size = (try? fileManager.attributesOfItem(atPath: modelFileURL.path)[.size] as? Int64) ?? 0
                if !validateSize(size, expected: model.expectedBytes) {
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
            state = fileManager.fileExists(atPath: modelFileURL.path) ? .installed : .notInstalled
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
        guard fileManager.fileExists(atPath: modelFileURL.path) else {
            lastError = LocalInferenceError.modelMissing.localizedDescription
            state = .failed(lastError!)
            return
        }
        guard LocalInferenceEngine.isLlamaRuntimeAvailable else {
            lastError = LocalInferenceError.notAvailable.localizedDescription
            state = .failed(lastError!)
            return
        }
        state = .loading
        lastError = nil
        do {
            try await engine.load(path: modelFileURL.path)
            state = .ready
        } catch {
            lastError = error.localizedDescription
            state = .failed(error.localizedDescription)
        }
    }

    func unload() async {
        state = .unloading
        await engine.cancel()
        await engine.unload()
        state = fileManager.fileExists(atPath: modelFileURL.path) ? .installed : .notInstalled
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

        // Si déjà installé valide → noop.
        if fileManager.fileExists(atPath: destination.path) {
            let size = (try? fileManager.attributesOfItem(atPath: destination.path)[.size] as? Int64) ?? 0
            if validateSize(size, expected: model.expectedBytes) {
                return
            }
            try? fileManager.removeItem(at: destination)
        }

        var existingBytes: Int64 = 0
        if fileManager.fileExists(atPath: partial.path) {
            existingBytes = (try? fileManager.attributesOfItem(atPath: partial.path)[.size] as? Int64) ?? 0
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
            // Range non supporté / partiel invalide → recommencer à zéro.
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
            let urlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            self.session = urlSession

            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 60 * 60
            if existingBytes > 0 {
                request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
            }
            let task = urlSession.downloadTask(with: request)
            self.downloadTask = task
            task.resume()
        }
    }

    private func validateInstalledFile(model: LocalModelDescriptor) throws {
        guard fileManager.fileExists(atPath: modelFileURL.path) else {
            throw LocalInferenceError.modelMissing
        }
        let size = (try? fileManager.attributesOfItem(atPath: modelFileURL.path)[.size] as? Int64) ?? 0
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
        installedBytes = size
    }

    private func validateSize(_ actual: Int64, expected: Int64) -> Bool {
        guard expected > 0, actual > 0 else { return false }
        let tolerance = Double(expected) * 0.05
        return abs(Double(actual - expected)) <= tolerance
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
            // 206 = reprise Range ; 200 = fichier complet (ignorer le partiel existant).
            let shouldAppend = existingBytes > 0 && status == 206 && fm.fileExists(atPath: partialURL.path)

            if shouldAppend {
                let handle = try FileHandle(forWritingTo: partialURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                let data = try Data(contentsOf: location)
                try handle.write(contentsOf: data)
            } else {
                if fm.fileExists(atPath: partialURL.path) {
                    try fm.removeItem(at: partialURL)
                }
                try fm.moveItem(at: location, to: partialURL)
            }

            // Atomic move vers le fichier final.
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: partialURL, to: destinationURL)
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
            // Range invalide — supprimer le partiel ; l’utilisateur relancera un téléchargement propre.
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
}
