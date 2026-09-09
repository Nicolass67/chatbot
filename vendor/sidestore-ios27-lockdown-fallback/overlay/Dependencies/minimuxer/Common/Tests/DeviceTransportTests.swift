//
//  DeviceTransportTests.swift
//  MinimuxerCommonTests
//

import XCTest
@testable import MinimuxerCommon

final class DeviceTransportTests: XCTestCase {
    func testPrefersRemotePairingWhenBothEndpointsAreUp() {
        let selected = DeviceTransportSelector.select(
            remotePairingReachable: true,
            lockdownReachable: true
        )
        XCTAssertEqual(selected, .rppairing)
    }

    func testFallsBackToLockdownWhenRemotePairingIsDown() {
        let selected = DeviceTransportSelector.select(
            remotePairingReachable: false,
            lockdownReachable: true
        )
        XCTAssertEqual(selected, .lockdown)
    }

    func testUnavailableWhenNeitherEndpointIsUp() {
        let selected = DeviceTransportSelector.select(
            remotePairingReachable: false,
            lockdownReachable: false
        )
        XCTAssertEqual(selected, .unavailable)
    }

    func testRemotePairingKeysDoNotForceRemotePairingWhenEndpointIsClosed() {
        let selected = DeviceTransportSelector.select(
            remotePairingReachable: false,
            lockdownReachable: true,
            pairingSupportsRemotePairing: true,
            pairingSupportsLockdown: true
        )
        XCTAssertEqual(selected, .lockdown)
        XCTAssertNotEqual(selected, .rppairing)
    }

    func testTunnelCreationFailureFallsBackToLockdownForCompatibleOperations() {
        let resolution = DeviceTransportSelector.resolveAfterRemotePairingFailure(
            operation: .lockdownCompatible,
            lockdownReachable: true,
            pairingSupportsLockdown: true
        )
        XCTAssertEqual(resolution, .use(.lockdown))
    }

    func testFakeMuxerNotRequiredWhenLockdownTCPIsUp() {
        XCTAssertFalse(
            DeviceTransportSelector.fakeMuxerRequiredForLockdown(
                muxerListening: false,
                lockdownReachable: true
            )
        )
        XCTAssertTrue(
            DeviceTransportSelector.fakeMuxerRequiredForLockdown(
                muxerListening: false,
                lockdownReachable: false
            )
        )
        XCTAssertFalse(
            DeviceTransportSelector.fakeMuxerRequiredForLockdown(
                muxerListening: true,
                lockdownReachable: false
            )
        )
    }

    func testOperationRequiringRemotePairingDoesNotLoopOnLockdown() {
        let resolution = DeviceTransportSelector.resolve(
            selected: .lockdown,
            operation: .requiresRemotePairing
        )
        XCTAssertEqual(resolution, .requiresRemotePairing)
    }

    func testHybridPairingFileReportsBothCapabilities() {
        let plist: [String: any Sendable] = [
            "private_key": Data(),
            "public_key": Data(),
            "identifier": "host",
            "WiFiMACAddress": "00:00:00:00:00:00",
            "SystemBUID": "buid",
            "RootPrivateKey": Data(),
            "HostPrivateKey": Data(),
            "HostID": "host-id",
            "RootCertificate": Data(),
            "UDID": "00008110-000170222186401E",
            "EscrowBag": Data(),
            "HostCertificate": Data(),
            "DeviceCertificate": Data()
        ]
        let caps = PairingFileParser.capabilities(from: plist)
        XCTAssertTrue(caps.supportsRemotePairing)
        XCTAssertTrue(caps.supportsLockdown)
        XCTAssertEqual(caps.lockdownUDID, "00008110-000170222186401E")

        // parse() still prefers RP keys first — transport selection must ignore that.
        let mode = try? PairingFileParser.validatePairingFile(from: plist)
        XCTAssertEqual(mode, .rppairing)
        let selected = DeviceTransportSelector.select(
            remotePairingReachable: false,
            lockdownReachable: true,
            pairingSupportsRemotePairing: caps.supportsRemotePairing,
            pairingSupportsLockdown: caps.supportsLockdown
        )
        XCTAssertEqual(selected, .lockdown)
    }
}
