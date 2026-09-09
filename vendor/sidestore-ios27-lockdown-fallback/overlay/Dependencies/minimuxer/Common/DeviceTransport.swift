//
//  DeviceTransport.swift
//  MinimuxerCommon
//
//  Transport selection is based on live endpoint reachability, not on pairing-file
//  keys, iOS version, Developer Mode, or LocalDevVPN being connected.
//

import Foundation

public enum DeviceTransport: String, Equatable, Sendable, CustomStringConvertible {
    case rppairing
    case lockdown
    case unavailable

    public var description: String { rawValue }
}

/// Operations SideStore may request from minimuxer.
public enum DeviceTransportOperation: String, Equatable, Sendable {
    /// UDID, lockdown values, AFC, instproxy, misagent, heartbeat.
    case lockdownCompatible
    /// JIT / debugserver via RSD, CoreDevice-only services.
    case requiresRemotePairing
}

public enum DeviceTransportResolution: Equatable, Sendable {
    case use(DeviceTransport)
    case requiresRemotePairing
    case unavailable
}

public struct DeviceTransportProbeResult: Equatable, Sendable {
    public let remotePairingReachable: Bool
    public let lockdownReachable: Bool
    public let remotePairingPort: UInt16
    public let lockdownPort: UInt16
    public let selected: DeviceTransport

    public var deviceReachable: Bool {
        selected != .unavailable
    }

    public init(
        remotePairingReachable: Bool,
        lockdownReachable: Bool,
        remotePairingPort: UInt16,
        lockdownPort: UInt16,
        selected: DeviceTransport
    ) {
        self.remotePairingReachable = remotePairingReachable
        self.lockdownReachable = lockdownReachable
        self.remotePairingPort = remotePairingPort
        self.lockdownPort = lockdownPort
        self.selected = selected
    }
}

public enum DeviceTransportSelector {
    /// Deterministic preferred transport from live probes.
    /// Pairing-file RP keys must not force `.rppairing` when 49152 is closed.
    public static func select(
        remotePairingReachable: Bool,
        lockdownReachable: Bool,
        pairingSupportsRemotePairing: Bool = true,
        pairingSupportsLockdown: Bool = true
    ) -> DeviceTransport {
        if remotePairingReachable && pairingSupportsRemotePairing {
            return .rppairing
        }
        if lockdownReachable && pairingSupportsLockdown {
            return .lockdown
        }
        return .unavailable
    }

    /// After RPPairing was preferred but the tunnel could not be created.
    public static func resolveAfterRemotePairingFailure(
        operation: DeviceTransportOperation,
        lockdownReachable: Bool,
        pairingSupportsLockdown: Bool
    ) -> DeviceTransportResolution {
        switch operation {
        case .requiresRemotePairing:
            return .requiresRemotePairing
        case .lockdownCompatible:
            if lockdownReachable && pairingSupportsLockdown {
                return .use(.lockdown)
            }
            return .unavailable
        }
    }

    /// Idevice lockdown talks to 62078 directly. The fake usbmuxd on :27015 is
    /// only required when that endpoint is down.
    public static func fakeMuxerRequiredForLockdown(
        muxerListening: Bool,
        lockdownReachable: Bool
    ) -> Bool {
        !muxerListening && !lockdownReachable
    }

    public static func resolve(
        selected: DeviceTransport,
        operation: DeviceTransportOperation
    ) -> DeviceTransportResolution {
        switch operation {
        case .lockdownCompatible:
            if selected == .unavailable {
                return .unavailable
            }
            return .use(selected)
        case .requiresRemotePairing:
            if selected == .rppairing {
                return .use(.rppairing)
            }
            if selected == .lockdown {
                return .requiresRemotePairing
            }
            return .unavailable
        }
    }
}
