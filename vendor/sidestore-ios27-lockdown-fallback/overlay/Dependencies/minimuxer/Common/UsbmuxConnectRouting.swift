//
//  UsbmuxConnectRouting.swift
//  MinimuxerCommon
//
//  Fake usbmuxd Connect must open lockdownd on the VPN Device IP (62078 is
//  reachable there) and dynamic services (misagent, afc, …) on loopback first.
//  Direct TCP to 10.7.0.1:<StartService port> BrokenPipes on iOS 27.
//

import Foundation

public enum UsbmuxConnectRouting {
    /// Client sends `PortNumber` as `port.to_be()` in a plist integer.
    public static func decodePortNumber(_ value: Any?) -> UInt16? {
        let raw: UInt32
        if let number = value as? NSNumber {
            raw = number.uint32Value
        } else if let i = value as? Int {
            raw = UInt32(truncatingIfNeeded: i)
        } else if let u = value as? UInt {
            raw = UInt32(truncatingIfNeeded: u)
        } else if let i = value as? Int64 {
            raw = UInt32(truncatingIfNeeded: i)
        } else if let u = value as? UInt64 {
            raw = UInt32(truncatingIfNeeded: u)
        } else {
            return nil
        }
        return UInt16(truncatingIfNeeded: raw).byteSwapped
    }

    /// Hosts to try for a usbmux Connect, in order.
    public static func destinationHosts(
        port: UInt16,
        deviceIp: String?,
        lockdownPort: UInt16 = MinimuxerConstants.lockdowndPort
    ) -> [String] {
        var hosts: [String] = []
        let device = sanitizedHost(deviceIp)
        if port == lockdownPort {
            appendUnique(&hosts, device)
            appendUnique(&hosts, "127.0.0.1")
        } else {
            appendUnique(&hosts, "127.0.0.1")
            appendUnique(&hosts, device)
        }
        if hosts.isEmpty {
            hosts.append("127.0.0.1")
        }
        return hosts
    }

    /// Direct TCP lockdown sessions: prefer loopback when 62078 answers there.
    public static func lockdownTcpHosts(deviceIp: String?, loopbackLockdownOpen: Bool) -> [String] {
        var hosts: [String] = []
        if loopbackLockdownOpen {
            appendUnique(&hosts, "127.0.0.1")
        }
        appendUnique(&hosts, sanitizedHost(deviceIp))
        if hosts.isEmpty {
            hosts.append("127.0.0.1")
        }
        return hosts
    }

    private static func sanitizedHost(_ ip: String?) -> String? {
        guard let ip, !ip.isEmpty, !ip.contains("/") else { return nil }
        return ip
    }

    private static func appendUnique(_ hosts: inout [String], _ host: String?) {
        guard let host, !hosts.contains(host) else { return }
        hosts.append(host)
    }
}
