//
//  UsbmuxConnectRoutingTests.swift
//  MinimuxerCommonTests
//

import XCTest
@testable import MinimuxerCommon

final class UsbmuxConnectRoutingTests: XCTestCase {
    func testDecodesLockdowndPortFromNetworkByteOrder() {
        let wire = UInt16(62078).byteSwapped
        XCTAssertEqual(UsbmuxConnectRouting.decodePortNumber(Int(wire)), 62078)
        XCTAssertEqual(UsbmuxConnectRouting.decodePortNumber(NSNumber(value: wire)), 62078)
    }

    func testLockdowndConnectPrefersDeviceIpThenLoopback() {
        XCTAssertEqual(
            UsbmuxConnectRouting.destinationHosts(port: 62078, deviceIp: "10.7.0.1"),
            ["10.7.0.1", "127.0.0.1"]
        )
    }

    func testDynamicServiceConnectPrefersLoopbackThenDeviceIp() {
        XCTAssertEqual(
            UsbmuxConnectRouting.destinationHosts(port: 41234, deviceIp: "10.7.0.1"),
            ["127.0.0.1", "10.7.0.1"]
        )
    }

    func testLockdownTcpPrefersLoopbackWhenOpen() {
        XCTAssertEqual(
            UsbmuxConnectRouting.lockdownTcpHosts(deviceIp: "10.7.0.1", loopbackLockdownOpen: true),
            ["127.0.0.1", "10.7.0.1"]
        )
        XCTAssertEqual(
            UsbmuxConnectRouting.lockdownTcpHosts(deviceIp: "10.7.0.1", loopbackLockdownOpen: false),
            ["10.7.0.1"]
        )
    }
}
