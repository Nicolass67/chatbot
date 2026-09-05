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

    private weak var session: AppSessionStore?
    private var refreshGeneration: UInt64 = 0
    private var lastAlertFingerprint: String?

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

    // MARK: - Actions

    func refresh() async {
        guard let client else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        loading = true
        defer {
            if generation == refreshGeneration {
                loading = false
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
        guard let client else { return }
        do {
            let power = try await client.wakePc()
            lastRepairMessage = power.message.isEmpty ? "Signal de réveil envoyé" : power.message
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
