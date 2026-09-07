import Foundation
import Network

/// Envoi local Wake-on-LAN (UDP magic packet) — même principe que les apps WoL du téléphone.
/// Complète le WoL Freebox distant (Worker) : utile quand le téléphone est sur le Wi‑Fi Freebox.
enum WakeOnLanSender {
    /// MACs cibles (Ethernet X520 + Wi‑Fi + I225). Surcharge Info.plist `ChatbotWolMacAddresses`.
    static var configuredMacAddresses: [String] {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "ChatbotWolMacAddresses") as? String {
            let parsed = raw
                .split(separator: ",")
                .map { normalizeMac(String($0)) }
                .filter { !$0.isEmpty }
            if !parsed.isEmpty { return parsed }
        }
        return [
            "9C:69:B4:60:70:6B", // Ethernet X520 (lien principal Freebox)
            "E8:BF:B8:5A:20:76", // Wi‑Fi BE200
            "D8:43:AE:1E:09:56", // Ethernet I225 carte mère
        ].map(normalizeMac)
    }

    /// Broadcasts / unicasts typiques Freebox + dual-LAN.
    static var defaultHosts: [String] {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "ChatbotWolBroadcastHosts") as? String {
            let parsed = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parsed.isEmpty { return parsed }
        }
        return [
            "255.255.255.255",
            "192.168.1.255",
            "192.168.8.255",
            "192.168.0.255",
            "192.168.1.168", // IP Ethernet connue
        ]
    }

    static func normalizeMac(_ raw: String) -> String {
        let hex = raw.uppercased().filter(\.isHexDigit)
        guard hex.count == 12 else { return "" }
        var parts: [String] = []
        var idx = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(idx, offsetBy: 2)
            parts.append(String(hex[idx..<next]))
            idx = next
        }
        return parts.joined(separator: ":")
    }

    static func magicPacket(for mac: String) -> Data? {
        let normalized = normalizeMac(mac)
        let hex = normalized.filter(\.isHexDigit)
        guard hex.count == 12 else { return nil }
        var macBytes = [UInt8]()
        var idx = hex.startIndex
        for _ in 0..<6 {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            macBytes.append(b)
            idx = next
        }
        var packet = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: macBytes)
        }
        return packet
    }

    /// Envoie les magic packets en best-effort (ne jette pas).
    static func sendConfigured() async {
        let macs = configuredMacAddresses
        let hosts = defaultHosts
        guard !macs.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for mac in macs {
                guard let packet = magicPacket(for: mac) else { continue }
                for host in hosts {
                    let packetCopy = packet
                    let hostCopy = host
                    group.addTask {
                        await send(packet: packetCopy, host: hostCopy, port: 9)
                        await send(packet: packetCopy, host: hostCopy, port: 7)
                    }
                }
            }
        }
    }

    private final class ResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private let cont: CheckedContinuation<Void, Never>

        init(_ cont: CheckedContinuation<Void, Never>) {
            self.cont = cont
        }

        func finish() {
            lock.lock()
            defer { lock.unlock() }
            guard !done else { return }
            done = true
            cont.resume()
        }
    }

    private static func send(packet: Data, host: String, port: UInt16) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let gate = ResumeGate(cont)
            let nwHost = NWEndpoint.Host(host)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                gate.finish()
                return
            }
            let connection = NWConnection(host: nwHost, port: nwPort, using: .udp)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(
                        content: packet,
                        completion: .contentProcessed { _ in
                            connection.cancel()
                            gate.finish()
                        }
                    )
                case .failed, .cancelled:
                    connection.cancel()
                    gate.finish()
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.2) {
                connection.cancel()
                gate.finish()
            }
        }
    }
}
