//
//  UsbmuxdProxyServer.swift
//  Minimuxer
//
//  Original Rust Implementation by @jkcoxson
//  Swift Port created by Magesh K on 02/03/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import Network
internal import DeviceGatewayAPI
internal import MinimuxerCommon

final internal class UsbmuxdProxyServer {
    let gateway: any DeviceGatewayAPI

    private var maxBufferLen: Int { MinimuxerConstants.usbmuxMaxPacketBufferLength }
    private var headerLen: Int { MinimuxerConstants.usbmuxHeaderLen }

    private(set) var started = false
    private(set) var isListening = false

    private var deviceUDID: String?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "minimuxer.UsbmuxdProxyServer", qos: .userInitiated)

    // Stable device state
    private var currentDeviceIp: String?
    private var currentEvent: String?

    init(gateway: any DeviceGatewayAPI) {
        self.gateway = gateway
    }

    func notifyDeviceAttached(tunnelPeerIp: String) {
        currentDeviceIp = tunnelPeerIp
        currentEvent = MinimuxerConstants.deviceAttach
    }
    func notifyDeviceDetached() {
        currentDeviceIp = nil
        currentEvent = MinimuxerConstants.deviceDetach
    }

    // Binds a TCP server on 127.0.0.1:27015 and accepts incoming connections
    // from libusbmuxd. This is our fake usbmuxd — it speaks
    // just enough of the usbmuxd protocol for the library to discover the
    // device, read the pairing record, and open services (AFC, lockdown, etc.).
    @discardableResult
    func start(udid: String) async throws -> Bool {
        guard !started else {
            verboseLog("[minimuxer] Already started UsbmuxdProxyServer, skipping")
            return false
        }
        deviceUDID = udid
        isListening = false

        guard let port = NWEndpoint.Port(rawValue: MinimuxerConstants.usbmuxdPort) else {
            throw MinimuxerError.connect("Invalid usbmuxd port: \(MinimuxerConstants.usbmuxdPort)")
        }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let newListener = try NWListener(using: params, on: port)

        return try await withCheckedThrowingContinuation { continuation in
            nonisolated(unsafe) var hasResponded = false

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                    case .ready:
                        verboseLog("[minimuxer] UsbmuxdProxyServer (NWListener) bound successfully to \(MinimuxerConstants.usbmuxdHost):\(MinimuxerConstants.usbmuxdPort)")
                        self.isListening = true
                        self.started = true
                        if !hasResponded {
                            hasResponded = true
                            continuation.resume(returning: true)
                        }
                    case .failed(let error):
                        debugLog("[minimuxer] UsbmuxdProxyServer listener failed with error: \(error)")
                        self.isListening = false
                        self.started = false
                        if !hasResponded {
                            hasResponded = true
                            continuation.resume(throwing: MinimuxerError.connect("UsbmuxdProxyServer failed to bind: \(error.localizedDescription)"))
                        }
                    case .cancelled:
                        self.isListening = false
                        self.started = false
                    default:
                        break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener = newListener
            newListener.start(queue: queue)
        }
    }

    func stop() async {
        guard started else { return }
        let currentListener = listener
        started = false
        isListening = false
        deviceUDID = nil
        listener = nil

        guard let currentListener = currentListener else { return }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            nonisolated(unsafe) var hasResponded = false
            currentListener.stateUpdateHandler = { state in
                if case .cancelled = state {
                    if !hasResponded {
                        hasResponded = true
                        continuation.resume()
                    }
                }
            }
            currentListener.cancel()
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readNextPacket(on: connection)
    }

    private func readNextPacket(on connection: NWConnection) {
        // 1. Read the 4-byte size header
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] sizeData, _, _, error in
            guard let self = self else { return }
            if let error = error {
                debugLog("[minimuxer] UsbmuxdProxyServer receive size error: \(error)")
                connection.cancel()
                return
            }
            guard let sizeData = sizeData, sizeData.count == 4 else {
                connection.cancel()
                return
            }

            let size = sizeData.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            guard size >= UInt32(self.headerLen) && size <= UInt32(self.maxBufferLen) else {
                debugLog("[minimuxer] UsbmuxdProxyServer invalid packet size: \(size)")
                connection.cancel()
                return
            }

            // 2. Read the remaining size - 4 bytes
            let bodyLen = Int(size - 4)
            connection.receive(minimumIncompleteLength: bodyLen, maximumLength: bodyLen) { [weak self] bodyData, _, _, bodyError in
                guard let self = self else { return }
                if let bodyError = bodyError {
                    debugLog("[minimuxer] UsbmuxdProxyServer receive body error: \(bodyError)")
                    connection.cancel()
                    return
                }
                guard let bodyData = bodyData, bodyData.count == bodyLen else {
                    connection.cancel()
                    return
                }

                var fullPacketData = sizeData
                fullPacketData.append(bodyData)

                self.processPacketData(fullPacketData, on: connection)
            }
        }
    }

    private func processPacketData(_ data: Data, on connection: NWConnection) {
        guard let packet = RawPacket(data: data) else {
            connection.cancel()
            return
        }
        guard let messageType = packet.plist["MessageType"] as? String else {
            readNextPacket(on: connection)
            return
        }
        if messageType == "Connect" {
            handleConnect(packet, on: connection)
            return
        }

        do {
            let response = try handlePacket(packet)
            let responsePacket = RawPacket(plist: response, version: 1, message: 8, tag: packet.tag)
            connection.send(content: responsePacket.data, completion: .contentProcessed({ error in
                if let error = error {
                    debugLog("[minimuxer] UsbmuxdProxyServer send error: \(error)")
                    connection.cancel()
                    return
                }
                self.readNextPacket(on: connection)
            }))
        } catch {
            debugLog("[minimuxer] UsbmuxdProxyServer handlePacket failed: \(error)")
            readNextPacket(on: connection)
        }
    }

    // Packet Handling
    // Responds to the only usbmuxd protocol message("ListDevices") that
    // idevice requires to establish lockdown session when using lockdown based pairing file
    // (lockdown requires UDID to start session, so our server responds with data read from pair file)
    private func handlePacket(_ packet: RawPacket) throws -> [String: Any] {
        guard let messageType = packet.plist["MessageType"] as? String else {
            throw MinimuxerError.connect("Malformed usbmuxd packet: missing MessageType field")
        }

        verboseLog("[minimuxer] usbmux message: \(messageType)")

        switch messageType {
            case "ListDevices":
                guard let udid = deviceUDID else {
                    throw MinimuxerError.invalidPairing(protocol: .lockdown, reason: "No device UDID available for ListDevices response")
                }
                let advertisedIp = currentDeviceIp ?? "127.0.0.1"
                let payload: [String: Any] = [
                    "DeviceID": 1,                                                      // non-zero ID
                    "Properties": [
                        "ConnectionType": "Network",                                    // using 'network' protocol of usbmuxd
                        "DeviceID": 1,                                                  // fake non-zero device id
                        "EscapedFullServiceName": "\(udid)._apple-mobdev2._tcp.local",  // advert for mds discovery
                        "InterfaceIndex": 0,                                            // don't care
                        "NetworkAddress": convertIp(advertisedIp),                      // metadata only; Connect picks the real host
                        "SerialNumber": udid                                            // device UDID
                    ]
                ]
                return ["DeviceList": [payload]]
            case "Listen":
                return ["MessageType": "Result", "Number": 0]
            case "ReadBUID":
                let buid = (self.gateway.pairingDataDict?["SystemBUID"] as? String) ?? "00000000-0000-0000-0000-000000000000"
                return ["BUID": buid]
            case "ReadPairRecord":
                guard let pairingData = self.gateway.pairingFileData else {
                    throw MinimuxerError.invalidPairing(protocol: .lockdown, reason: "No pairing file data available for ReadPairRecord")
                }
                return ["PairRecordData": pairingData]
            default:
                debugLog("[minimuxer] WARN: unknown message type: \(messageType)")
                throw MinimuxerError.connect("Unsupported usbmuxd message type: \(messageType)")
        }
    }

    private func handleConnect(_ packet: RawPacket, on client: NWConnection) {
        guard let port = UsbmuxConnectRouting.decodePortNumber(packet.plist["PortNumber"]) else {
            debugLog("[usbmux] Connect missing/invalid PortNumber")
            sendConnectResult(3, tag: packet.tag, on: client) {
                client.cancel()
            }
            return
        }
        let hosts = UsbmuxConnectRouting.destinationHosts(port: port, deviceIp: currentDeviceIp)
        debugLog("[usbmux] Connect port=\(port) hosts=\(hosts)")
        connectFirstAvailable(hosts: hosts, port: port, index: 0) { device in
            guard let device else {
                debugLog("[usbmux] Connect port=\(port) refused on all hosts")
                self.sendConnectResult(3, tag: packet.tag, on: client) {
                    client.cancel()
                }
                return
            }
            self.sendConnectResult(0, tag: packet.tag, on: client) {
                self.splice(client, device)
            }
        }
    }

    private func sendConnectResult(_ number: UInt32, tag: UInt32, on connection: NWConnection, then: (() -> Void)? = nil) {
        let packet = RawPacket(
            plist: ["MessageType": "Result", "Number": number],
            version: 1,
            message: 8,
            tag: tag
        )
        connection.send(content: packet.data, completion: .contentProcessed({ error in
            if let error {
                debugLog("[usbmux] Connect result send failed: \(error)")
                connection.cancel()
                return
            }
            then?()
        }))
    }

    private func connectFirstAvailable(
        hosts: [String],
        port: UInt16,
        index: Int,
        completion: @escaping (NWConnection?) -> Void
    ) {
        guard index < hosts.count, let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(nil)
            return
        }
        let host = hosts[index]
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        var finished = false
        let timeout = DispatchWorkItem { [weak conn] in
            guard !finished else { return }
            finished = true
            conn?.cancel()
            debugLog("[usbmux] Connect \(host):\(port) timeout")
            self.connectFirstAvailable(hosts: hosts, port: port, index: index + 1, completion: completion)
        }
        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard !finished else { return }
                finished = true
                timeout.cancel()
                debugLog("[usbmux] Connect \(host):\(port) ready")
                completion(conn)
            case .failed(let error):
                guard !finished else { return }
                finished = true
                timeout.cancel()
                debugLog("[usbmux] Connect \(host):\(port) failed: \(error)")
                conn.cancel()
                self.connectFirstAvailable(hosts: hosts, port: port, index: index + 1, completion: completion)
            default:
                break
            }
        }
        conn.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 0.8, execute: timeout)
    }

    private func splice(_ a: NWConnection, _ b: NWConnection) {
        pump(from: a, to: b)
        pump(from: b, to: a)
    }

    private func pump(from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            if let error {
                debugLog("[usbmux] splice receive error: \(error)")
                from.cancel()
                to.cancel()
                return
            }
            if let data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { sendErr in
                    if let sendErr {
                        debugLog("[usbmux] splice send error: \(sendErr)")
                        from.cancel()
                        to.cancel()
                        return
                    }
                    self.pump(from: from, to: to)
                })
                return
            }
            if isComplete {
                to.cancel()
                from.cancel()
            } else {
                self.pump(from: from, to: to)
            }
        }
    }

    // Encodes an IPv4 address into the 152-byte sockaddr_storage layout that
    // libusbmuxd expects in the NetworkAddress field of the device properties.
    private func convertIp(_ ip: String) -> Data {
        var sa = sockaddr_in()
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_family = sa_family_t(AF_INET)

        var data = Data(count: 152)
        if inet_pton(AF_INET, ip, &sa.sin_addr) == 1 {
            withUnsafeBytes(of: sa) { src in
                data.withUnsafeMutableBytes { dst in
                    dst.copyMemory(from: src)
                }
            }
        }
        return data
    }
}
