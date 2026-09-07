import Foundation
import Combine

@MainActor
final class InfrastructureStore: ObservableObject {
    @Published private(set) var status: InfrastructureStatusDTO?
    @Published private(set) var incidents: [IncidentDTO] = []
    @Published private(set) var repairing = false
    @Published private(set) var loading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var lastRepairMessage: String?
    /// Incrémenté après la fenêtre de grâce — force le refresh des bannières.
    @Published private(set) var alertEpoch: UInt64 = 0

    private weak var session: AppSessionStore?
    private var refreshGeneration: UInt64 = 0
    private var lastAlertFingerprint: String?
    /// Première détection d’un problème par service (debounce UX).
    private var problemFirstSeenAt: [String: Date] = [:]
    private var graceTask: Task<Void, Never>?

    /// Grace courte pour éviter le flash « Réparer » pendant le healthcheck (~2–3 s).
    private let problemGraceInterval: TimeInterval = 2.4
    private let outageGraceInterval: TimeInterval = 1.2

    func bind(session: AppSessionStore) {
        self.session = session
    }

    private var client: APIClient? {
        guard let session else { return nil }
        return APIClient(baseURL: session.baseURL, token: session.token)
    }

    // MARK: - Convenience

    var overallState: InfrastructureOverallState {
        status?.overallState ?? .unknown
    }

    var isDegraded: Bool {
        status?.isDegraded == true
    }

    var isPcOnline: Bool {
        status?.powerState.isOnline == true
    }

    var assistantAvailability: ServiceAvailability {
        status?.availability(forServiceId: InfrastructureServiceID.assistant) ?? .unknown
    }

    var webSearchAvailability: ServiceAvailability {
        status?.availability(forServiceId: InfrastructureServiceID.webSearch) ?? .unknown
    }

    var chatbotAvailability: ServiceAvailability {
        status?.availability(forServiceId: InfrastructureServiceID.chatbot) ?? .unknown
    }

    var statusSubtitle: String? {
        guard isDegraded else { return nil }
        return "Un problème"
    }

    /// Snapshot reçu — les problèmes ne s’affichent qu’après grâce (pas pendant le 1er check).
    var canSurfaceServiceAlerts: Bool {
        status != nil
    }

    /// PC explicitement éteint (pas « unknown » pendant le check).
    var isPcConfirmedOffline: Bool {
        status?.powerState == .offline
    }

    // MARK: - Actions

    func refresh() async {
        guard let client else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        loading = true
        defer {
            if generation == refreshGeneration {
                loading = false
                reconcileProblemGraceWindow()
            }
        }
        do {
            async let statusTask = client.fetchInfrastructureStatus()
            async let incidentsTask = client.fetchInfrastructureIncidents()
            let (nextStatus, nextIncidents) = try await (statusTask, incidentsTask)
            guard generation == refreshGeneration else { return }
            status = nextStatus
            incidents = nextIncidents
            lastRefresh = Date()
            clearAlertIfRecovered()
        } catch is CancellationError {
            return
        } catch {
            guard generation == refreshGeneration else { return }
            publishAlert(error.localizedDescription)
        }
    }

    /// Bannière utilisateur : uniquement après confirmation (pas pendant loading/unknown/warm-up).
    func shouldSurfaceBanner(forServiceId id: String) -> Bool {
        guard canSurfaceServiceAlerts else { return false }
        guard let service = status?.service(id: id) else { return false }
        if service.isWarmingUp {
            problemFirstSeenAt.removeValue(forKey: id)
            return false
        }
        let availability = service.availability
        switch availability {
        case .available, .unknown:
            problemFirstSeenAt.removeValue(forKey: id)
            return false
        case .unavailable:
            return isProblemConfirmed(id: id, grace: outageGraceInterval)
        case .degraded:
            return isProblemConfirmed(id: id, grace: problemGraceInterval)
        }
    }

    private func isProblemConfirmed(id: String, grace: TimeInterval) -> Bool {
        let now = Date()
        if problemFirstSeenAt[id] == nil {
            problemFirstSeenAt[id] = now
        }
        guard let first = problemFirstSeenAt[id] else { return false }
        return now.timeIntervalSince(first) >= grace
    }

    private func reconcileProblemGraceWindow() {
        guard let status else {
            problemFirstSeenAt.removeAll()
            graceTask?.cancel()
            graceTask = nil
            return
        }
        let watched = [
            InfrastructureServiceID.assistant,
            InfrastructureServiceID.webSearch,
            InfrastructureServiceID.chatbot,
        ]
        var pendingDelay: TimeInterval?
        for id in watched {
            guard let service = status.service(id: id) else {
                problemFirstSeenAt.removeValue(forKey: id)
                continue
            }
            if service.isWarmingUp || !service.availability.needsAttention {
                problemFirstSeenAt.removeValue(forKey: id)
                continue
            }
            let grace = service.availability == .unavailable
                ? outageGraceInterval
                : problemGraceInterval
            if problemFirstSeenAt[id] == nil {
                problemFirstSeenAt[id] = Date()
            }
            if let first = problemFirstSeenAt[id] {
                let remaining = grace - Date().timeIntervalSince(first)
                if remaining > 0 {
                    pendingDelay = min(pendingDelay ?? remaining, remaining)
                }
            }
        }
        graceTask?.cancel()
        guard let pendingDelay, pendingDelay > 0 else { return }
        graceTask = Task { [weak self] in
            let ns = UInt64(pendingDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns + 50_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.alertEpoch &+= 1
            }
        }
    }

    @discardableResult
    func diagnoseAndRepair() async -> RepairResultDTO? {
        guard let client else { return nil }
        repairing = true
        defer { repairing = false }
        do {
            _ = try await client.diagnoseInfrastructure()
            let result = try await client.repairInfrastructure()
            lastRepairMessage = result.message.isEmpty ? "Réparation demandée" : result.message
            await refresh()
            return result
        } catch is CancellationError {
            return nil
        } catch {
            publishAlert(error.localizedDescription)
            return nil
        }
    }

    @discardableResult
    func repairService(id: String) async -> RepairResultDTO? {
        guard let client else { return nil }
        repairing = true
        defer { repairing = false }
        do {
            let result = try await client.repairInfrastructure(serviceId: id)
            lastRepairMessage = result.message.isEmpty
                ? "Réparation demandée pour \(id)"
                : result.message
            await refresh()
            return result
        } catch is CancellationError {
            return nil
        } catch {
            publishAlert(error.localizedDescription)
            return nil
        }
    }

    func wake() async {
        // 1) Magic packet local d’abord (comme les apps WoL du téléphone).
        await WakeOnLanSender.sendConfigured()
        guard let client else {
            lastRepairMessage = "WoL local envoyé — reconnecte-toi pour le réveil distant Freebox."
            return
        }
        do {
            // 2) Freebox distant via Worker + demande boot KV (comme l’ancien site web).
            let power = try await client.wakePc()
            lastRepairMessage = power.message.isEmpty
                ? "Réveil local + Freebox envoyés"
                : power.message
            // 3) Poll court comme la page offline web (attendre le retour du PC).
            await pollUntilReachable(timeoutSeconds: 90)
        } catch {
            // Même si le Worker échoue, le packet local peut suffire sur le LAN.
            lastRepairMessage =
                "WoL local envoyé. Distant : \(error.localizedDescription)"
            await pollUntilReachable(timeoutSeconds: 60)
            if status == nil || isPcConfirmedOffline {
                publishAlert(error.localizedDescription)
            }
        }
    }

    /// Attend que le Worker voie le backend (ou que le status infra réponde).
    private func pollUntilReachable(timeoutSeconds: Double) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var attempt = 0
        while Date() < deadline {
            attempt += 1
            if let client {
                if let online = try? await client.fetchWorkerBackendOnline(), online {
                    lastRepairMessage = "PC en ligne (vérification \(attempt))"
                    await refresh()
                    return
                }
            }
            await refresh()
            if isPcOnline || chatbotAvailability == .available {
                lastRepairMessage = "PC en ligne"
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    /// PC déjà allumé : démarre la stack via Worker (sans WoL).
    func startServices() async {
        guard let client else { return }
        do {
            let power = try await client.startServices()
            lastRepairMessage = power.message.isEmpty
                ? "Démarrage des services demandé"
                : power.message
            await refresh()
        } catch {
            publishAlert(error.localizedDescription)
        }
    }

    /// Relance complète de la stack (PC déjà allumé).
    func restartServices() async {
        guard let client else { return }
        do {
            let power = try await client.restartServices()
            lastRepairMessage = power.message.isEmpty
                ? "Relance des services demandée"
                : power.message
            await refresh()
        } catch {
            publishAlert(error.localizedDescription)
        }
    }

    func shutdown() async {
        guard let client else { return }
        do {
            let power = try await client.shutdownPc()
            lastRepairMessage = power.message.isEmpty ? "Extinction planifiée" : power.message
            await refresh()
        } catch {
            publishAlert(error.localizedDescription)
        }
    }

    func restart() async {
        guard let client else { return }
        do {
            let power = try await client.restartPc()
            lastRepairMessage = power.message.isEmpty ? "Redémarrage planifié" : power.message
            await refresh()
        } catch {
            publishAlert(error.localizedDescription)
        }
    }

    func clearError() {
        errorMessage = nil
        lastAlertFingerprint = nil
    }

    // MARK: - Alerts (dedupe)

    private func publishAlert(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let fingerprint = trimmed.lowercased()
        if fingerprint == lastAlertFingerprint { return }
        lastAlertFingerprint = fingerprint
        errorMessage = trimmed
    }

    private func clearAlertIfRecovered() {
        if status?.overallState == .healthy {
            errorMessage = nil
            lastAlertFingerprint = nil
        }
    }
}
