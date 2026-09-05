import Foundation

// MARK: - Overall / power

enum InfrastructureOverallState: String, Codable, Hashable, Sendable {
    case healthy
    case degraded
    case recovering
    case offline
    case error
    case unknown

    init(flexible raw: String?) {
        guard let raw, let v = Self(rawValue: raw.lowercased()) else {
            self = .unknown
            return
        }
        self = v
    }

    var isDegraded: Bool {
        switch self {
        case .healthy, .unknown: return false
        case .degraded, .recovering, .offline, .error: return true
        }
    }

    var frenchLabel: String {
        switch self {
        case .healthy: return "Tout va bien"
        case .degraded: return "Problème détecté"
        case .recovering: return "Récupération en cours"
        case .offline: return "PC hors ligne"
        case .error: return "Erreur système"
        case .unknown: return "État inconnu"
        }
    }
}

enum InfrastructurePowerState: String, Codable, Hashable, Sendable {
    case online
    case offline
    case starting
    case stopping
    case unknown

    init(flexible raw: String?) {
        guard let raw else { self = .unknown; return }
        switch raw.lowercased() {
        case "online", "on": self = .online
        case "offline", "off": self = .offline
        case "starting": self = .starting
        case "stopping": self = .stopping
        default: self = .unknown
        }
    }

    var isOnline: Bool { self == .online || self == .starting }

    var frenchLabel: String {
        switch self {
        case .online: return "Allumé"
        case .offline: return "Éteint"
        case .starting: return "Démarrage…"
        case .stopping: return "Extinction…"
        case .unknown: return "Inconnu"
        }
    }
}

enum ServiceProcessState: String, Codable, Hashable, Sendable {
    case stopped
    case starting
    case running
    case stopping
    case unknown

    init(flexible raw: String?) {
        guard let raw, let v = Self(rawValue: raw.lowercased()) else {
            self = .unknown
            return
        }
        self = v
    }
}

enum ServiceHealthState: String, Codable, Hashable, Sendable {
    case healthy
    case unhealthy
    case unknown

    init(flexible raw: String?) {
        guard let raw, let v = Self(rawValue: raw.lowercased()) else {
            self = .unknown
            return
        }
        self = v
    }

    var isOk: Bool { self == .healthy }
}

enum ServiceReadinessState: String, Codable, Hashable, Sendable {
    case ready
    case notReady = "not_ready"
    case loading
    case unknown

    init(flexible raw: String?) {
        guard let raw else { self = .unknown; return }
        switch raw.lowercased() {
        case "ready": self = .ready
        case "not_ready", "not-ready", "notready": self = .notReady
        case "loading": self = .loading
        default: self = .unknown
        }
    }

    var isReady: Bool { self == .ready }
}

enum ServiceAvailability: String, Hashable, Sendable {
    case available
    case degraded
    case unavailable
    case unknown

    var frenchLabel: String {
        switch self {
        case .available: return "Disponible"
        case .degraded: return "Ralenti"
        case .unavailable: return "Indisponible"
        case .unknown: return "Inconnu"
        }
    }

    /// Problème confirmé (pas « inconnu » ni encore en cours de check).
    var needsAttention: Bool {
        switch self {
        case .available, .unknown: return false
        case .degraded, .unavailable: return true
        }
    }
}

// MARK: - DTOs

struct ServiceStatusDTO: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let humanName: String
    let category: String?
    let criticality: String?
    let process: ServiceProcessState
    let health: ServiceHealthState
    let readiness: ServiceReadinessState
    let summary: String
    let lastCheckAt: String?
    let lastRecoveryAt: String?
    let restartCount: Int
    let incidentId: String?
    let crashLoop: Bool

    init(
        id: String,
        displayName: String,
        humanName: String,
        category: String? = nil,
        criticality: String? = nil,
        process: ServiceProcessState = .unknown,
        health: ServiceHealthState = .unknown,
        readiness: ServiceReadinessState = .unknown,
        summary: String = "",
        lastCheckAt: String? = nil,
        lastRecoveryAt: String? = nil,
        restartCount: Int = 0,
        incidentId: String? = nil,
        crashLoop: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.humanName = humanName
        self.category = category
        self.criticality = criticality
        self.process = process
        self.health = health
        self.readiness = readiness
        self.summary = summary
        self.lastCheckAt = lastCheckAt
        self.lastRecoveryAt = lastRecoveryAt
        self.restartCount = restartCount
        self.incidentId = incidentId
        self.crashLoop = crashLoop
    }

    var preferredName: String {
        let human = humanName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !human.isEmpty { return human }
        let display = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        return id
    }

    var availability: ServiceAvailability {
        if crashLoop { return .unavailable }
        if process == .stopped || health == .unhealthy { return .unavailable }
        // Démarrage / healthcheck : pas une panne utilisateur.
        if process == .starting || readiness == .loading {
            return .unknown
        }
        if readiness == .notReady {
            return .degraded
        }
        if health == .healthy && (readiness == .ready || readiness == .unknown) {
            return .available
        }
        if health == .unknown && process == .unknown { return .unknown }
        return .degraded
    }

    /// Service encore en warm-up / healthcheck — ne pas afficher de bannière.
    var isWarmingUp: Bool {
        process == .starting || readiness == .loading
    }
}

extension ServiceStatusDTO: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, serviceId
        case displayName, name
        case humanName, label
        case category, criticality
        case process, processState
        case health, healthState
        case readiness, readinessState
        case summary, message, statusMessage
        case lastCheckAt, lastCheck, checkedAt
        case lastRecoveryAt, lastRecovery
        case restartCount, restarts
        case incidentId
        case crashLoop, crash_loop
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawId = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decodeIfPresent(String.self, forKey: .serviceId)
            ?? ""
        id = rawId
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
            ?? c.decodeIfPresent(String.self, forKey: .name)
            ?? rawId
        humanName = try c.decodeIfPresent(String.self, forKey: .humanName)
            ?? c.decodeIfPresent(String.self, forKey: .label)
            ?? displayName
        category = try c.decodeIfPresent(String.self, forKey: .category)
        criticality = try c.decodeIfPresent(String.self, forKey: .criticality)
        process = ServiceProcessState(flexible:
            try c.decodeIfPresent(String.self, forKey: .process)
                ?? c.decodeIfPresent(String.self, forKey: .processState)
        )
        health = ServiceHealthState(flexible:
            try c.decodeIfPresent(String.self, forKey: .health)
                ?? c.decodeIfPresent(String.self, forKey: .healthState)
        )
        readiness = ServiceReadinessState(flexible:
            try c.decodeIfPresent(String.self, forKey: .readiness)
                ?? c.decodeIfPresent(String.self, forKey: .readinessState)
        )
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
            ?? c.decodeIfPresent(String.self, forKey: .message)
            ?? c.decodeIfPresent(String.self, forKey: .statusMessage)
            ?? ""
        lastCheckAt = try c.decodeIfPresent(String.self, forKey: .lastCheckAt)
            ?? c.decodeIfPresent(String.self, forKey: .lastCheck)
            ?? c.decodeIfPresent(String.self, forKey: .checkedAt)
        lastRecoveryAt = try c.decodeIfPresent(String.self, forKey: .lastRecoveryAt)
            ?? c.decodeIfPresent(String.self, forKey: .lastRecovery)
        restartCount = try c.decodeIfPresent(Int.self, forKey: .restartCount)
            ?? c.decodeIfPresent(Int.self, forKey: .restarts)
            ?? 0
        incidentId = try c.decodeIfPresent(String.self, forKey: .incidentId)
        crashLoop = try c.decodeIfPresent(Bool.self, forKey: .crashLoop)
            ?? c.decodeIfPresent(Bool.self, forKey: .crash_loop)
            ?? false
    }
}

struct InfrastructureStatusDTO: Hashable, Sendable {
    let overallState: InfrastructureOverallState
    let powerState: InfrastructurePowerState
    let generatedAt: String?
    let supervisorAlive: Bool
    let message: String
    let services: [ServiceStatusDTO]
    let activeRepairId: String?

    init(
        overallState: InfrastructureOverallState,
        powerState: InfrastructurePowerState,
        generatedAt: String? = nil,
        supervisorAlive: Bool = true,
        message: String = "",
        services: [ServiceStatusDTO] = [],
        activeRepairId: String? = nil
    ) {
        self.overallState = overallState
        self.powerState = powerState
        self.generatedAt = generatedAt
        self.supervisorAlive = supervisorAlive
        self.message = message
        self.services = services
        self.activeRepairId = activeRepairId
    }

    var isDegraded: Bool { overallState.isDegraded }

    func service(id: String) -> ServiceStatusDTO? {
        services.first { $0.id == id }
    }

    func availability(forServiceId id: String) -> ServiceAvailability {
        guard let service = service(id: id) else { return .unknown }
        return service.availability
    }
}

extension InfrastructureStatusDTO: Decodable {
    private enum CodingKeys: String, CodingKey {
        case overallState, state, status, overall
        case powerState, power
        case generatedAt, timestamp, checkedAt
        case supervisorAlive, supervisor
        case message, summary
        case services
        case activeRepairId, repairId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overallState = InfrastructureOverallState(flexible:
            try c.decodeIfPresent(String.self, forKey: .overallState)
                ?? c.decodeIfPresent(String.self, forKey: .state)
                ?? c.decodeIfPresent(String.self, forKey: .status)
                ?? c.decodeIfPresent(String.self, forKey: .overall)
        )
        if let powerObj = try? c.nestedContainer(keyedBy: PowerKeys.self, forKey: .power),
           let nested = try powerObj.decodeIfPresent(String.self, forKey: .state) {
            powerState = InfrastructurePowerState(flexible: nested)
        } else {
            powerState = InfrastructurePowerState(flexible:
                try c.decodeIfPresent(String.self, forKey: .powerState)
                    ?? c.decodeIfPresent(String.self, forKey: .power)
            )
        }
        generatedAt = try c.decodeIfPresent(String.self, forKey: .generatedAt)
            ?? c.decodeIfPresent(String.self, forKey: .timestamp)
            ?? c.decodeIfPresent(String.self, forKey: .checkedAt)
        if let alive = try c.decodeIfPresent(Bool.self, forKey: .supervisorAlive) {
            supervisorAlive = alive
        } else if let nested = try? c.nestedContainer(keyedBy: SupervisorKeys.self, forKey: .supervisor),
                  let alive = try nested.decodeIfPresent(Bool.self, forKey: .alive) {
            supervisorAlive = alive
        } else {
            supervisorAlive = true
        }
        message = try c.decodeIfPresent(String.self, forKey: .message)
            ?? c.decodeIfPresent(String.self, forKey: .summary)
            ?? ""
        services = try c.decodeIfPresent([ServiceStatusDTO].self, forKey: .services) ?? []
        activeRepairId = try c.decodeIfPresent(String.self, forKey: .activeRepairId)
            ?? c.decodeIfPresent(String.self, forKey: .repairId)
    }

    private enum PowerKeys: String, CodingKey { case state }
    private enum SupervisorKeys: String, CodingKey { case alive }
}

struct RepairActionResultDTO: Hashable, Sendable {
    let type: String
    let serviceId: String
    let ok: Bool
    let detail: String
}

extension RepairActionResultDTO: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type, action
        case serviceId, service
        case ok, success
        case detail, message
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type)
            ?? c.decodeIfPresent(String.self, forKey: .action)
            ?? ""
        serviceId = try c.decodeIfPresent(String.self, forKey: .serviceId)
            ?? c.decodeIfPresent(String.self, forKey: .service)
            ?? ""
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok)
            ?? c.decodeIfPresent(Bool.self, forKey: .success)
            ?? false
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
            ?? c.decodeIfPresent(String.self, forKey: .message)
            ?? ""
    }
}

struct RepairResultDTO: Hashable, Sendable {
    let planId: String?
    let incidentId: String?
    let status: String
    let actions: [RepairActionResultDTO]
    let repairedServices: [String]
    let untouchedServices: [String]
    let durationMs: Int?
    let message: String

    init(
        planId: String? = nil,
        incidentId: String? = nil,
        status: String,
        actions: [RepairActionResultDTO] = [],
        repairedServices: [String] = [],
        untouchedServices: [String] = [],
        durationMs: Int? = nil,
        message: String = ""
    ) {
        self.planId = planId
        self.incidentId = incidentId
        self.status = status
        self.actions = actions
        self.repairedServices = repairedServices
        self.untouchedServices = untouchedServices
        self.durationMs = durationMs
        self.message = message
    }

    var succeeded: Bool {
        let s = status.lowercased()
        return s == "success" || s == "partial" || s == "queued" || s == "already_in_progress" || s == "skipped"
    }
}

extension RepairResultDTO: Decodable {
    private enum CodingKeys: String, CodingKey {
        case planId, id
        case incidentId
        case status, result, state
        case actions
        case repairedServices, repaired
        case untouchedServices, untouched
        case durationMs, duration
        case message, summary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        planId = try c.decodeIfPresent(String.self, forKey: .planId)
            ?? c.decodeIfPresent(String.self, forKey: .id)
        incidentId = try c.decodeIfPresent(String.self, forKey: .incidentId)
        status = try c.decodeIfPresent(String.self, forKey: .status)
            ?? c.decodeIfPresent(String.self, forKey: .result)
            ?? c.decodeIfPresent(String.self, forKey: .state)
            ?? "unknown"
        actions = try c.decodeIfPresent([RepairActionResultDTO].self, forKey: .actions) ?? []
        repairedServices = try c.decodeIfPresent([String].self, forKey: .repairedServices)
            ?? c.decodeIfPresent([String].self, forKey: .repaired)
            ?? []
        untouchedServices = try c.decodeIfPresent([String].self, forKey: .untouchedServices)
            ?? c.decodeIfPresent([String].self, forKey: .untouched)
            ?? []
        if let ms = try c.decodeIfPresent(Int.self, forKey: .durationMs) {
            durationMs = ms
        } else if let d = try c.decodeIfPresent(Double.self, forKey: .duration) {
            durationMs = Int(d)
        } else {
            durationMs = nil
        }
        message = try c.decodeIfPresent(String.self, forKey: .message)
            ?? c.decodeIfPresent(String.self, forKey: .summary)
            ?? ""
    }
}

struct IncidentDTO: Identifiable, Hashable, Sendable {
    let id: String
    let serviceId: String
    let detectedAt: String
    let resolvedAt: String?
    let category: String?
    let diagnosis: String
    let actions: [String]
    let result: String
    let restartCount: Int
    let durationMs: Int?

    var isOpen: Bool {
        let r = result.lowercased()
        return r == "open" || r == "circuit_open" || resolvedAt == nil
    }
}

extension IncidentDTO: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, incidentId
        case serviceId, service
        case detectedAt, startedAt, createdAt
        case resolvedAt, endedAt
        case category
        case diagnosis, message, summary
        case actions
        case result, status
        case restartCount, restarts
        case durationMs, duration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decodeIfPresent(String.self, forKey: .incidentId)
            ?? UUID().uuidString
        serviceId = try c.decodeIfPresent(String.self, forKey: .serviceId)
            ?? c.decodeIfPresent(String.self, forKey: .service)
            ?? ""
        detectedAt = try c.decodeIfPresent(String.self, forKey: .detectedAt)
            ?? c.decodeIfPresent(String.self, forKey: .startedAt)
            ?? c.decodeIfPresent(String.self, forKey: .createdAt)
            ?? ""
        resolvedAt = try c.decodeIfPresent(String.self, forKey: .resolvedAt)
            ?? c.decodeIfPresent(String.self, forKey: .endedAt)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        diagnosis = try c.decodeIfPresent(String.self, forKey: .diagnosis)
            ?? c.decodeIfPresent(String.self, forKey: .message)
            ?? c.decodeIfPresent(String.self, forKey: .summary)
            ?? ""
        actions = try c.decodeIfPresent([String].self, forKey: .actions) ?? []
        result = try c.decodeIfPresent(String.self, forKey: .result)
            ?? c.decodeIfPresent(String.self, forKey: .status)
            ?? "open"
        restartCount = try c.decodeIfPresent(Int.self, forKey: .restartCount)
            ?? c.decodeIfPresent(Int.self, forKey: .restarts)
            ?? 0
        if let ms = try c.decodeIfPresent(Int.self, forKey: .durationMs) {
            durationMs = ms
        } else if let d = try c.decodeIfPresent(Double.self, forKey: .duration) {
            durationMs = Int(d)
        } else {
            durationMs = nil
        }
    }
}

struct PowerStatusDTO: Hashable, Sendable {
    let powerState: InfrastructurePowerState
    let message: String
    let ok: Bool

    init(powerState: InfrastructurePowerState, message: String = "", ok: Bool = true) {
        self.powerState = powerState
        self.message = message
        self.ok = ok
    }

    var isOnline: Bool { powerState.isOnline }
}

extension PowerStatusDTO: Decodable {
    private enum CodingKeys: String, CodingKey {
        case powerState, state, power, status
        case message, summary
        case ok, success
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        powerState = InfrastructurePowerState(flexible:
            try c.decodeIfPresent(String.self, forKey: .powerState)
                ?? c.decodeIfPresent(String.self, forKey: .state)
                ?? c.decodeIfPresent(String.self, forKey: .power)
                ?? c.decodeIfPresent(String.self, forKey: .status)
        )
        message = try c.decodeIfPresent(String.self, forKey: .message)
            ?? c.decodeIfPresent(String.self, forKey: .summary)
            ?? ""
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok)
            ?? c.decodeIfPresent(Bool.self, forKey: .success)
            ?? true
    }
}

/// Known service ids (backend registry).
enum InfrastructureServiceID {
    static let assistant = "lm_studio"
    static let webSearch = "searxng"
    static let chatbot = "nextjs"
    static let tunnel = "cloudflared"
    static let docker = "docker"
}
