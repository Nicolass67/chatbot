import Foundation
import Combine
import Metal

/// Gestion téléchargement / installation / chargement du GGUF local.
/// Ne touche **jamais** aux modèles LM Studio du PC.
///
/// Stockage : sandbox app `Library/Application Support/Models/`.
/// Une réinstallation / sideload IPA **recrée le conteneur** → le GGUF disparaît.
/// Aucun flag UserDefaults ne peut indiquer « installé » sans fichier réel.
@MainActor
final class LocalModelManager: ObservableObject {
    static let shared = LocalModelManager()

    @Published private(set) var state: LocalModelInstallState = .notInstalled
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastError: String?
    @Published private(set) var isMetalAvailable: Bool = false
    @Published private(set) var activeModelId: String = LocalModelDescriptor.primary.id
    @Published private(set) var installedBytes: Int64 = 0

    /// Verrou exclusif tenu pour toute la durée d’une mutation (y compris pendant `await`).
    /// `busyAction` UI n’est **pas** une protection suffisante.
    private(set) var exclusiveOperation: ModelExclusiveOperation?

    private var downloadTask: URLSessionDownloadTask?
    private var downloadDelegate: DownloadDelegate?
    private var session: URLSession?
    private var installGeneration: UInt64 = 0
    /// Une seule Task d’auto-load à la fois (évite double `loadIntoEngine` + lastError parasite).
    private var autoLoadTask: Task<Void, Never>?

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

    /// Installé = fichier GGUF réellement présent, taille attendue, magic valide.
    var isInstalled: Bool {
        presence.isFullyInstalled
    }

    var presence: LocalModelPresence {
        LocalModelFileAudit.probe(
            at: modelFileURL,
            expectedBytes: activeDescriptor.expectedBytes,
            fileManager: fileManager
        )
    }

    var isReady: Bool {
        if case .ready = state { return true }
        if case .generating = state { return true }
        return false
    }

    init() {
        refreshMetalAvailability()
        refreshInstalledState()
        LocalModelFileAudit.log("local-ai:lifecycle", [
            "event": "init",
            "path": modelFilePath,
            "presence": String(describing: presence),
            "entries": LocalModelFileAudit.directoryListing(at: modelsDirectory).joined(separator: "|"),
        ])
    }

    func refreshMetalAvailability() {
#if targetEnvironment(simulator)
        isMetalAvailable = false
#else
        isMetalAvailable = MTLCreateSystemDefaultDevice() != nil
#endif
    }

    /// Recalcule l’état strictement depuis le disque.
    /// Jamais de `.installed` / `.ready` si le fichier n’est pas un GGUF valide.
    func refreshInstalledState() {
        let probe = presence
        recordStorageAudit("refresh", presence: probe)

        switch state {
        case .downloading, .verifying:
            // Ne pas écraser un téléchargement en cours.
            return
        case .loading, .unloading, .generating:
            // Si le fichier a disparu (ex. sideload pendant l’usage), forcer la correction.
            if !probe.isFullyInstalled {
                state = .notInstalled
                installedBytes = 0
                progress = 0
                lastError = missingFileDiagnostic()
                logLoadTrace("refresh-while-busy-forced-notInstalled")
            }
            return
        default:
            break
        }

        applyPresenceToState(probe, clearTransientErrors: true)
    }

    // MARK: - Install / Download

    func install(model: LocalModelDescriptor = .primary) async {
        let initialState = state.statusLabel
        guard var remoteURL = model.downloadURL else {
            lastError = "Ce modèle n’est pas encore téléchargeable."
            state = .failed(lastError!)
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "early-exit",
                "reason": "not-downloadable",
                "model": model.id,
                "initialState": initialState,
            ])
            return
        }
        guard beginExclusive(.install) else { return }
        defer { endExclusive(.install) }

        if case .downloading = state {
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "early-exit",
                "reason": "already-downloading",
                "model": model.id,
                "initialState": initialState,
            ])
            return
        }
        if case .verifying = state {
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "early-exit",
                "reason": "already-verifying",
                "model": model.id,
                "initialState": initialState,
            ])
            return
        }

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
        let dir = modelsDirectory
        installGeneration &+= 1
        let generation = installGeneration
        lastError = nil
        progress = 0
        state = .downloading(progress: 0)
        defer {
            // C — sortie complète de install() (tous chemins).
            LocalModelFileAudit.snapshotFS(point: "C-after-install-exit", finalPath: modelFilePath)
        }

        LocalModelFileAudit.log("local-ai:download", [
            "phase": "install-start",
            "model": model.id,
            "generation": generation,
            "initialState": initialState,
            "final.path": fileSystemPath(modelFileURL),
            "partial.path": fileSystemPath(partialDownloadURL),
            "url": remoteURL.absoluteString,
            "expectedBytes": model.expectedBytes,
            "models.entries": LocalModelFileAudit.directoryListing(at: dir).joined(separator: "|"),
        ])

        do {
            try await download(from: remoteURL, model: model, generation: generation)
            guard generation == installGeneration else {
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "generation-mismatch",
                    "where": "after-download",
                    "generation": generation,
                    "currentGeneration": installGeneration,
                ])
                return
            }
            state = .verifying
            try validateInstalledFile(model: model)
            guard generation == installGeneration else {
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "generation-mismatch",
                    "where": "after-validation",
                    "generation": generation,
                    "currentGeneration": installGeneration,
                ])
                return
            }
            let probe = LocalModelFileAudit.probe(
                at: modelFileURL,
                expectedBytes: model.expectedBytes,
                fileManager: fileManager
            )
            guard case .installed(let size) = probe else {
                throw LocalInferenceError.modelMissing
            }
            installedBytes = size
            progress = 1
            state = .installed
            lastError = nil
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "installed-state-set",
                "exists": true,
                "size": size,
                "expectedBytes": model.expectedBytes,
                "path": modelFilePath,
                "models.entries": LocalModelFileAudit.directoryListing(at: modelsDirectory).joined(separator: "|"),
            ])
            // B — immédiatement après installed-state-set
            LocalModelFileAudit.snapshotFS(point: "B-after-installed-state-set", finalPath: modelFilePath)
        } catch is CancellationError {
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "early-exit",
                "reason": "cancellation",
                "generation": generation,
                "currentGeneration": installGeneration,
            ])
            guard generation == installGeneration else {
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "generation-mismatch",
                    "where": "cancellation-handler",
                    "generation": generation,
                    "currentGeneration": installGeneration,
                ])
                return
            }
            applyPresenceToState(presence, clearTransientErrors: false)
        } catch {
            guard generation == installGeneration else {
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "generation-mismatch",
                    "where": "failure-handler",
                    "generation": generation,
                    "currentGeneration": installGeneration,
                    "error": error.localizedDescription,
                ])
                return
            }
            lastError = error.localizedDescription
            state = .failed(error.localizedDescription)
            let probe = presence
            if case .invalid = probe {
                LocalModelFileAudit.logFileDelete(
                    path: modelFilePath,
                    caller: "LocalModelManager.install/failure-invalid"
                )
                try? fileManager.removeItem(at: modelFileURL)
            }
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "failed",
                "error": error.localizedDescription,
                "final.exists": actualFileExists,
                "final.size": actualFileSize,
                "path": modelFilePath,
                "models.entries": LocalModelFileAudit.directoryListing(at: modelsDirectory).joined(separator: "|"),
            ])
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
            progress = 0
            applyPresenceToState(presence, clearTransientErrors: false)
        }
    }

    func deleteModel() async {
        guard beginExclusive(.delete) else { return }
        defer { endExclusive(.delete) }
        cancelDownload()
        await performUnload()
        if fileManager.fileExists(atPath: modelFilePath) {
            LocalModelFileAudit.logFileDelete(path: modelFilePath, caller: "LocalModelManager.deleteModel")
        }
        try? fileManager.removeItem(at: modelFileURL)
        try? fileManager.removeItem(at: partialDownloadURL)
        installedBytes = 0
        progress = 0
        lastError = nil
        state = .notInstalled
        LocalModelFileAudit.log("local-ai:lifecycle", [
            "event": "delete",
            "path": modelFilePath,
            "models.entries": LocalModelFileAudit.directoryListing(at: modelsDirectory).joined(separator: "|"),
        ])
    }

    // MARK: - Engine

    /// Auto-chargement au démarrage / bascule « Toujours local ».
    /// - Ne télécharge / n’installe jamais.
    /// - No-op si déjà ready, absent, ou load déjà en cours.
    /// - Respecte `ModelExclusiveOperation` via `loadIntoEngine`.
    func requestAutoLoadIfNeeded(wantsLocalExecution: Bool) {
        guard wantsLocalExecution else { return }
        guard autoLoadTask == nil else { return }
        autoLoadTask = Task { @MainActor in
            defer { self.autoLoadTask = nil }
            await self.performAutoLoadIfNeeded()
        }
    }

    func performAutoLoadIfNeeded() async {
        refreshInstalledState()
        let loading: Bool = {
            if case .loading = state { return true }
            return false
        }()
        guard LocalModelAutoLoadPolicy.shouldAttemptLoad(
            wantsLocalExecution: true,
            isInstalled: isInstalled,
            isReady: isReady,
            exclusiveBusy: exclusiveOperation != nil,
            isLoading: loading
        ) else { return }
        await loadIntoEngine()
    }

    func loadIntoEngine() async {
        guard beginExclusive(.load) else { return }
        defer {
            logLoadTrace("defer")
            endExclusive(.load)
            logLoadTrace("end")
        }

        logLoadTrace("start")

        // E — tout début de load / Charger (manager)
        LocalModelFileAudit.snapshotFS(point: "E-loadIntoEngine-start", finalPath: modelFilePath)
        LocalModelFileAudit.logFSOp(
            "refreshInstalledState",
            phase: "before",
            result: "pending",
            watchedFinalPath: modelFilePath
        )
        logLoadTrace("before-refresh")
        LocalModelFileAudit.snapshotFS(point: "E-before-refreshInstalledState", finalPath: modelFilePath)
        refreshInstalledState()
        LocalModelFileAudit.snapshotFS(point: "E-after-refreshInstalledState", finalPath: modelFilePath)
        logLoadTrace("after-refresh")
        LocalModelFileAudit.logFSOp(
            "refreshInstalledState",
            phase: "after",
            result: "done",
            watchedFinalPath: modelFilePath
        )
        // Strict : aucun appel llama si le GGUF n’est pas réellement installé.
        guard isInstalled else {
            lastError = missingFileDiagnostic()
            state = .notInstalled
            installedBytes = 0
            LocalModelFileAudit.log("local-ai:lifecycle", [
                "event": "load-blocked-not-installed",
                "path": modelFilePath,
                "exists": actualFileExists,
                "size": actualFileSize,
                "models.entries": LocalModelFileAudit.directoryListing(at: modelsDirectory).joined(separator: "|"),
            ])
            LocalModelFileAudit.snapshotFS(point: "E-load-blocked-not-installed", finalPath: modelFilePath)
            logLoadTrace("end-blocked-not-installed")
            return
        }
        guard LocalInferenceEngine.isLlamaRuntimeAvailable else {
            lastError = LocalInferenceError.notAvailable.localizedDescription
            state = .installed
            logLoadTrace("end-runtime-unavailable")
            return
        }

        let path = modelFilePath
        state = .loading
        lastError = nil
        do {
            LocalModelFileAudit.snapshotFS(point: "E-before-engine-load", finalPath: path)
            logLoadTrace("before-libllama-load")
            try await engine.load(path: path)
            logLoadTrace("after-libllama-load")
            LocalModelFileAudit.snapshotFS(point: "E-after-engine-load", finalPath: path)
            // Re-vérifier après load (TOCTOU / sideload parallèle).
            if isInstalled {
                state = .ready
                logLoadTrace("success-ready")
            } else {
                logLoadTrace("before-unload")
                await engine.unload()
                logLoadTrace("after-unload")
                state = .notInstalled
                lastError = missingFileDiagnostic()
                logLoadTrace("success-but-file-missing")
            }
        } catch {
            lastError = error.localizedDescription
            logLoadTrace("catch")
            LocalModelFileAudit.snapshotFS(point: "E-after-engine-load-error", finalPath: path)
            applyPresenceToState(presence, clearTransientErrors: false)
            logLoadTrace("after-catch-applyPresence")
        }
    }

    func unload() async {
        guard beginExclusive(.unload) else { return }
        defer { endExclusive(.unload) }
        await performUnload()
    }

    func markGenerating(_ active: Bool) {
        if active {
            if state == .ready {
                guard beginExclusive(.generate) else { return }
                state = .generating
            }
        } else if state == .generating {
            state = isInstalled ? .ready : .notInstalled
            endExclusive(.generate)
        }
    }

    // MARK: - Exclusive gate

    /// Verrou tenu pendant toute l’opération (y compris `await`). Refus explicite si occupé.
    @discardableResult
    func beginExclusive(_ op: ModelExclusiveOperation) -> Bool {
        if let current = exclusiveOperation {
            let message =
                "Opération « \(current.rawValue) » en cours — « \(op.rawValue) » refusé."
            lastError = message
            LocalModelFileAudit.log("local-ai:lifecycle", [
                "event": "exclusive-rejected",
                "requested": op.rawValue,
                "active": current.rawValue,
            ])
            return false
        }
        exclusiveOperation = op
        return true
    }

    func endExclusive(_ op: ModelExclusiveOperation) {
        if exclusiveOperation == op {
            exclusiveOperation = nil
        }
    }

    private func performUnload() async {
        state = .unloading
        await engine.cancel()
        await engine.unload()
        applyPresenceToState(presence, clearTransientErrors: false)
    }

    private func logLoadTrace(_ phase: String) {
        LocalModelFileAudit.log("local-ai:load-trace", [
            "phase": phase,
            "fileExists": actualFileExists,
            "fileSize": actualFileSize,
            "state": state.statusLabel,
            "lastError": lastError ?? "",
            "exclusiveOperation": exclusiveOperation?.rawValue ?? "nil",
        ])
    }

    // MARK: - Private download

    private func download(from remoteURL: URL, model: LocalModelDescriptor, generation: UInt64) async throws {
        let destination = modelFileURL
        let partial = partialDownloadURL

        let existing = LocalModelFileAudit.probe(
            at: destination,
            expectedBytes: model.expectedBytes,
            fileManager: fileManager
        )
        if case .installed(let size) = existing {
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "early-exit",
                "reason": "already-installed",
                "size": size,
                "path": fileSystemPath(destination),
            ])
            return
        }
        if case .invalid = existing {
            LocalModelFileAudit.logFileDelete(
                path: fileSystemPath(destination),
                caller: "LocalModelManager.download/replace-invalid"
            )
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

        LocalModelFileAudit.log("local-ai:download", [
            "phase": "perform",
            "url": remoteURL.absoluteString,
            "existingPartialBytes": existingBytes,
            "expectedBytes": model.expectedBytes,
        ])

        do {
            try await performDownload(
                remoteURL: remoteURL,
                model: model,
                generation: generation,
                existingBytes: existingBytes,
                partial: partial,
                destination: destination
            )
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "download-end",
                "result": "success",
                "generation": generation,
                "final.path": fileSystemPath(destination),
                "final.exists": fileManager.fileExists(atPath: fileSystemPath(destination)),
                "final.size": (try? fileManager.attributesOfItem(atPath: fileSystemPath(destination))[.size] as? Int64) ?? 0,
            ])
        } catch is CancellationError {
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "download-end",
                "result": "failure",
                "reason": "cancellation",
                "generation": generation,
            ])
            throw CancellationError()
        } catch {
            if existingBytes > 0 {
                try? fileManager.removeItem(at: partial)
                do {
                    try await performDownload(
                        remoteURL: remoteURL,
                        model: model,
                        generation: generation,
                        existingBytes: 0,
                        partial: partial,
                        destination: destination
                    )
                    LocalModelFileAudit.log("local-ai:download", [
                        "phase": "download-end",
                        "result": "success",
                        "retryAfterPartialFailure": true,
                        "generation": generation,
                        "final.path": fileSystemPath(destination),
                        "final.exists": fileManager.fileExists(atPath: fileSystemPath(destination)),
                        "final.size": (try? fileManager.attributesOfItem(atPath: fileSystemPath(destination))[.size] as? Int64) ?? 0,
                    ])
                } catch {
                    LocalModelFileAudit.log("local-ai:download", [
                        "phase": "download-end",
                        "result": "failure",
                        "retryAfterPartialFailure": true,
                        "generation": generation,
                        "error": error.localizedDescription,
                        "errorDomain": (error as NSError).domain,
                        "errorCode": (error as NSError).code,
                    ])
                    throw error
                }
            } else {
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "download-end",
                    "result": "failure",
                    "generation": generation,
                    "error": error.localizedDescription,
                    "errorDomain": (error as NSError).domain,
                    "errorCode": (error as NSError).code,
                ])
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
                remoteURL: remoteURL,
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
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "task-created",
                "url": remoteURL.absoluteString,
                "taskIdentifier": task.taskIdentifier,
                "existingBytes": existingBytes,
                "generation": generation,
            ])
            task.resume()
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "task-resumed",
                "url": remoteURL.absoluteString,
                "taskIdentifier": task.taskIdentifier,
                "resumeCalled": true,
            ])
        }
    }

    private func validateInstalledFile(model: LocalModelDescriptor) throws {
        let probe = LocalModelFileAudit.probe(
            at: modelFileURL,
            expectedBytes: model.expectedBytes,
            fileManager: fileManager
        )
        recordStorageAudit("validation après téléchargement/move", presence: probe)
        switch probe {
        case .missing:
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "early-exit",
                "reason": "final-missing-at-validation",
                "path": modelFilePath,
            ])
            throw LocalInferenceError.modelMissing
        case .invalid(let size, let sizeOK, let magicOK):
            LocalModelFileAudit.logFileDelete(
                path: modelFilePath,
                caller: "LocalModelManager.validateInstalledFile/invalid"
            )
            try? fileManager.removeItem(at: modelFileURL)
            if !sizeOK {
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "incorrect-size",
                    "where": "validateInstalledFile",
                    "actualBytes": size,
                    "expectedBytes": model.expectedBytes,
                ])
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
            if !magicOK {
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "invalid-gguf-magic",
                    "where": "validateInstalledFile",
                    "actualBytes": size,
                ])
                throw NSError(
                    domain: "LocalModelManager",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Le fichier téléchargé n’est pas un GGUF (en-tête invalide). Réessaie l’installation."
                    ]
                )
            }
            throw LocalInferenceError.modelMissing
        case .installed(let size):
            installedBytes = size
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "validateInstalledFile",
                "result": "pass",
                "actualBytes": size,
                "expectedBytes": model.expectedBytes,
                "path": modelFilePath,
            ])
        }
    }

    private func applyPresenceToState(_ probe: LocalModelPresence, clearTransientErrors: Bool) {
        switch probe {
        case .installed(let size):
            installedBytes = size
            state = .installed
            if clearTransientErrors,
               lastError?.contains("invalide") == true
                || lastError?.contains("introuvable") == true
                || lastError?.contains("absent") == true {
                lastError = nil
            }
        case .invalid(let size, _, _):
            installedBytes = size
            state = .notInstalled
            lastError = "Fichier modèle invalide ou incomplet (\(byteLabel(size))). Supprimez puis réinstallez."
            logLoadTrace("applyPresence-invalid-notInstalled")
        case .missing:
            installedBytes = 0
            progress = 0
            state = .notInstalled
            // Intentionnel : ne touche pas lastError — peut laisser une UI sans message d’erreur.
            logLoadTrace("applyPresence-missing-notInstalled")
        }
    }

    private func fileSystemPath(_ url: URL) -> String {
        url.path(percentEncoded: false)
    }

    private func byteLabel(_ bytes: Int64) -> String {
        String(format: "%.0f Mo", Double(bytes) / 1_048_576.0)
    }

    private func missingFileDiagnostic() -> String {
        let dir = modelsDirectory
        let contents = LocalModelFileAudit.directoryListing(at: dir)
        if contents.isEmpty {
            return "Modèle GGUF introuvable dans Models/ (conteneur app vide — réinstallez après un sideload IPA). Relancez Installer."
        }
        return "Modèle GGUF introuvable (\(activeDescriptor.filename)). Dossier Models: \(contents.joined(separator: ", ")). Relancez Installer."
    }

    /// Trace de cycle de vie sans contenu de fichier ni donnée utilisateur.
    private func recordStorageAudit(_ event: String, presence: LocalModelPresence) {
        let path = modelFilePath
        let partial = partialDownloadURL
        LocalModelFileAudit.log("local-ai:storage", [
            "event": event,
            "presence": String(describing: presence),
            "final.exists": actualFileExists,
            "final.readable": actualFileIsReadable,
            "final.size": actualFileSize,
            "expectedBytes": activeDescriptor.expectedBytes,
            "partial.exists": fileManager.fileExists(atPath: fileSystemPath(partial)),
            "models.entries": LocalModelFileAudit.directoryListing(at: modelsDirectory).joined(separator: "|"),
            "final.path": path,
        ])
    }
}

// MARK: - URLSession download delegate

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let remoteURL: URL
    private let partialURL: URL
    private let destinationURL: URL
    private let expectedBytes: Int64
    private let existingBytes: Int64
    private let onProgress: @Sendable (Double) -> Void
    private let onComplete: @Sendable (Result<Void, Error>) -> Void
    private var finished = false
    private let lock = NSLock()
    /// Bucket 0…20 (= pas de 5 %) pour logs périodiques didWriteData.
    private var lastProgressBucket: Int = -1

    init(
        remoteURL: URL,
        partialURL: URL,
        destinationURL: URL,
        expectedBytes: Int64,
        existingBytes: Int64,
        onProgress: @escaping @Sendable (Double) -> Void,
        onComplete: @escaping @Sendable (Result<Void, Error>) -> Void
    ) {
        self.remoteURL = remoteURL
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

        let bucket = Int((fraction * 20.0).rounded(.down))
        if bucket != lastProgressBucket {
            lastProgressBucket = bucket
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "progress",
                "taskIdentifier": downloadTask.taskIdentifier,
                "totalBytesWritten": written,
                "totalBytesExpected": total,
                "percent": String(format: "%.1f", fraction * 100),
            ])
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let fm = FileManager.default
            let http = downloadTask.response as? HTTPURLResponse
            let status = http?.statusCode ?? -1
            let headerLength = http?.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init)
            let responseLength = http?.expectedContentLength ?? -1
            let tempPath = location.path(percentEncoded: false)
            let tempExists = fm.fileExists(atPath: tempPath)
            let tempSize = (try? fm.attributesOfItem(atPath: tempPath)[.size] as? Int64) ?? 0
            let tempReadable = fm.isReadableFile(atPath: tempPath)
            let parent = destinationURL.deletingLastPathComponent()

            LocalModelFileAudit.log("local-ai:download-finished", [
                "taskIdentifier": downloadTask.taskIdentifier,
                "location": tempPath,
                "exists": tempExists,
                "size": tempSize,
                "readable": tempReadable,
                "httpStatus": status,
                "contentLengthHeader": headerLength.map(String.init) ?? "nil",
                "expectedContentLength": responseLength,
                "expectedBytes": expectedBytes,
                "url": remoteURL.absoluteString,
                "models.entries.before": LocalModelFileAudit.directoryListing(at: parent).joined(separator: "|"),
            ])

            guard (200...299).contains(status) else {
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "http-non-2xx",
                    "httpStatus": status,
                    "taskIdentifier": downloadTask.taskIdentifier,
                ])
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
            guard tempExists, tempSize > 0 else {
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "temp-file-absent",
                    "exists": tempExists,
                    "size": tempSize,
                    "taskIdentifier": downloadTask.taskIdentifier,
                    "location": tempPath,
                ])
                throw NSError(
                    domain: "LocalModelManager",
                    code: 4,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Téléchargement terminé sans fichier temporaire (exists=\(tempExists), size=\(tempSize))."
                    ]
                )
            }

            let shouldAppend = existingBytes > 0 && status == 206 && fm.fileExists(atPath: partialURL.path(percentEncoded: false))
            let partialPath = partialURL.path(percentEncoded: false)

            do {
                if shouldAppend {
                    try Self.appendFile(from: location, onto: partialURL)
                    try? fm.removeItem(at: location)
                } else {
                    if fm.fileExists(atPath: partialPath) {
                        try fm.removeItem(at: partialURL)
                    }
                    try Self.moveOrCopy(location, to: partialURL)
                }
            } catch {
                LocalModelFileAudit.log("local-ai:download-move", [
                    "phase": "temp-to-partial",
                    "source": tempPath,
                    "source.exists": fm.fileExists(atPath: tempPath),
                    "destination": partialPath,
                    "destination.exists": fm.fileExists(atPath: partialPath),
                    "destination.size": (try? fm.attributesOfItem(atPath: partialPath)[.size] as? Int64) ?? 0,
                    "error": error.localizedDescription,
                    "taskIdentifier": downloadTask.taskIdentifier,
                ])
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "move-failed",
                    "where": "temp-to-partial",
                    "error": error.localizedDescription,
                ])
                throw error
            }

            let partialExists = fm.fileExists(atPath: partialPath)
            let partialSize = (try? fm.attributesOfItem(atPath: partialPath)[.size] as? Int64) ?? 0
            LocalModelFileAudit.log("local-ai:download-move", [
                "phase": "temp-to-partial",
                "source": tempPath,
                "source.exists": fm.fileExists(atPath: tempPath),
                "destination": partialPath,
                "destination.exists": partialExists,
                "destination.size": partialSize,
                "error": "nil",
                "taskIdentifier": downloadTask.taskIdentifier,
            ])

            let partialMagic = LocalModelFileAudit.isGGUFMagic(at: partialURL, fileManager: fm)
            let partialSizeOK = LocalModelFileAudit.validateSize(partialSize, expected: expectedBytes)
            let partialValid = partialExists && partialSizeOK && partialMagic
            LocalModelFileAudit.log("local-ai:download", [
                "phase": "partial-validation",
                "exists": partialExists,
                "actualBytes": partialSize,
                "expectedBytes": expectedBytes,
                "magicGGUF": partialMagic,
                "sizeOK": partialSizeOK,
                "validationResult": partialValid ? "pass" : "fail",
                "partial.path": partialPath,
            ])

            guard partialExists, partialSize > 0 else {
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "partial-absent-after-move",
                    "exists": partialExists,
                    "size": partialSize,
                ])
                throw NSError(
                    domain: "LocalModelManager",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "Fichier partiel absent après move depuis le temp URLSession."]
                )
            }

            let destinationPath = destinationURL.path(percentEncoded: false)
            do {
                if fm.fileExists(atPath: destinationPath) {
                    try fm.removeItem(at: destinationURL)
                }
                try Self.moveOrCopy(partialURL, to: destinationURL)
            } catch {
                LocalModelFileAudit.log("local-ai:download-move-final", [
                    "source": partialPath,
                    "destination": destinationPath,
                    "destination.exists": fm.fileExists(atPath: destinationPath),
                    "destination.size": (try? fm.attributesOfItem(atPath: destinationPath)[.size] as? Int64) ?? 0,
                    "error": error.localizedDescription,
                    "taskIdentifier": downloadTask.taskIdentifier,
                ])
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "move-failed",
                    "where": "partial-to-final",
                    "error": error.localizedDescription,
                ])
                throw error
            }

            let destinationExists = fm.fileExists(atPath: destinationPath)
            let destinationReadable = fm.isReadableFile(atPath: destinationPath)
            let destinationSize = (try? fm.attributesOfItem(atPath: destinationPath)[.size] as? Int64) ?? 0
            let magicOK = LocalModelFileAudit.isGGUFMagic(at: destinationURL, fileManager: fm)
            LocalModelFileAudit.log("local-ai:download-move-final", [
                "source": partialPath,
                "destination": destinationPath,
                "destination.exists": destinationExists,
                "destination.size": destinationSize,
                "destination.readable": destinationReadable,
                "destination.ggufMagic": magicOK,
                "expectedBytes": expectedBytes,
                "error": "nil",
                "taskIdentifier": downloadTask.taskIdentifier,
                "models.entries.after": LocalModelFileAudit.directoryListing(at: parent).joined(separator: "|"),
            ])
            guard destinationExists, destinationSize > 0 else {
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "final-absent-after-move",
                    "exists": destinationExists,
                    "size": destinationSize,
                ])
                throw NSError(
                    domain: "LocalModelManager",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Move GGUF terminé sans fichier final lisible."]
                )
            }
            // A — immédiatement après download-move-final réussi
            LocalModelFileAudit.snapshotFS(point: "A-after-download-move-final", finalPath: destinationPath)
            if !LocalModelFileAudit.validateSize(destinationSize, expected: expectedBytes) {
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "incorrect-size",
                    "where": "after-final-move-log-only",
                    "actualBytes": destinationSize,
                    "expectedBytes": expectedBytes,
                    "note": "guard-unchanged-size-check-deferred-to-validateInstalledFile",
                ])
            }
            finish(.success(()))
        } catch {
            LocalModelFileAudit.log("local-ai:download-move", [
                "phase": "error",
                "error": error.localizedDescription,
            ])
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            let ns = error as NSError
            LocalModelFileAudit.log("local-ai:download-complete", [
                "taskIdentifier": task.taskIdentifier,
                "error": String(describing: type(of: error)),
                "errorDomain": ns.domain,
                "errorCode": ns.code,
                "localizedDescription": error.localizedDescription,
            ])
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled {
                LocalModelFileAudit.log("local-ai:download", [
                    "phase": "early-exit",
                    "reason": "cancellation",
                    "taskIdentifier": task.taskIdentifier,
                ])
                finish(.failure(CancellationError()))
                return
            }
            if let response = task.response as? HTTPURLResponse, response.statusCode == 416 {
                try? FileManager.default.removeItem(at: partialURL)
            }
            finish(.failure(error))
            return
        }
        LocalModelFileAudit.log("local-ai:download-complete", [
            "taskIdentifier": task.taskIdentifier,
            "error": "nil",
            "errorDomain": "nil",
            "errorCode": "nil",
            "localizedDescription": "nil",
        ])
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
            let ns = error as NSError
            LocalModelFileAudit.log("local-ai:download-move", [
                "phase": "move-failed-copy-fallback",
                "error": error.localizedDescription,
                "errno": ns.code,
                "from": from.path(percentEncoded: false),
                "to": to.path(percentEncoded: false),
            ])
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
