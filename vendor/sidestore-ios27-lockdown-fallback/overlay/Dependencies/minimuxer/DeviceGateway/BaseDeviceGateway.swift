//
//  BaseDeviceGateway.swift
//  Minimuxer
//
//  Created by Magesh K on 05/09/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import MinimuxerCommon

enum AbstractClassError: Error, Sendable {
    case abstractInitializerInvoked
    case abstractMethodInvoked
}

open class BaseDeviceGateway: @unchecked Sendable {
    public package(set) var pairingFileType: PairingProtocol = .unknown
    public package(set) var pairingCapabilities: PairingFileCapabilities = .none
    public package(set) var selectedTransport: DeviceTransport = .unavailable
    public package(set) var lastRemotePairingReachable: Bool = false
    public package(set) var lastLockdownReachable: Bool = false
    public package(set) var pairingDataDict: [String: any Sendable]? = nil

    public package(set) var pairingFileData: Data? = nil {
        didSet {
            guard let pairingFileData else {
                self.pairingDataDict = nil
                return
            }
            self.pairingDataDict = try? PropertyListSerialization.propertyList(
                from: pairingFileData,
                options: [],
                format: nil
            ) as? [String: any Sendable]
        }
    }

    public package(set) var deviceEndpointIp: String? = nil
    public package(set) var isInitialized: Bool = false
    private var protocolPorts: [PairingProtocol: UInt16] = [:]

    package init() throws {
        if Self.self === BaseDeviceGateway.self {
            throw AbstractClassError.abstractInitializerInvoked
        }
    }

    public func setPairingFileData(_ data: Data?) {
        self.pairingFileData = data
    }

    public func setPairingFileType(_ type: PairingProtocol) {
        self.pairingFileType = type
    }

    public func setInitialized(_ initialized: Bool) {
        self.isInitialized = initialized
    }

    public func getPairingFileType() -> PairingProtocol {
        pairingFileType
    }

    public func applySelectedTransport(_ transport: DeviceTransport) throws {
        switch transport {
        case .unavailable:
            debugLog("[transport] selected=unavailable")
            selectedTransport = .unavailable
        case .rppairing:
            guard pairingCapabilities.supportsRemotePairing else {
                debugLog("[transport] operation requires RPPairing")
                debugLog("[transport] RPPairing unavailable")
                selectedTransport = .unavailable
                throw DeviceGatewayError(
                    .requiresRemotePairing,
                    reason: "RPPairing endpoint was selected but the pairing file has no RPPairing keys"
                )
            }
            debugLog("[transport] selected=rppairing")
            selectedTransport = .rppairing
            if pairingFileType != .rppairing {
                setPairingFileType(.rppairing)
                invalidateConnection()
            }
        case .lockdown:
            guard pairingCapabilities.supportsLockdown else {
                debugLog("[transport] Lockdown unavailable: pairing file has no lockdown keys")
                selectedTransport = .unavailable
                throw DeviceGatewayError(
                    .connectionFailed,
                    reason: "Lockdown endpoint is reachable but the pairing file has no lockdown keys"
                )
            }
            debugLog("[transport] selected=lockdown")
            selectedTransport = .lockdown
            if pairingFileType != .lockdown {
                setPairingFileType(.lockdown)
                invalidateConnection()
            }
        }
    }

    public func recordTransportProbe(_ result: DeviceTransportProbeResult) {
        lastRemotePairingReachable = result.remotePairingReachable
        lastLockdownReachable = result.lockdownReachable
    }

    public func getPort(for protocol: PairingProtocol) -> UInt16 {
        protocolPorts[`protocol`] ?? `protocol`.defaultPort
    }

    private var logTag: String {
        String(describing: type(of: self))
    }

    public func setPort(_ port: UInt16, for protocol: PairingProtocol) {
        debugLog("[\(logTag)] setPort(\(port), for: .\(`protocol`)) called")
        guard protocolPorts[`protocol`] != port else { return }
        protocolPorts[`protocol`] = port
        invalidateConnection()
    }

    public func setDeviceEndpointIp(_ ip: String?) {
        debugLog("[\(logTag)] setDeviceEndpointIp(\(ip ?? "nil")) called")
        guard deviceEndpointIp != ip else {
            debugLog("[\(logTag)] setDeviceEndpointIp: IP is already \(ip ?? "nil"), skipping invalidation")
            return
        }
        deviceEndpointIp = ip
        invalidateConnection()
    }

    open func setLogging(_ enabled: Bool) {
        DeviceGatewayLogging.setLogging(enabled)
        debugLog("[\(logTag)] setLogging(\(enabled)) called")
    }

    open func invalidateConnection() {
        // Subclasses override to invalidate cached handles/tunnels
    }
}
