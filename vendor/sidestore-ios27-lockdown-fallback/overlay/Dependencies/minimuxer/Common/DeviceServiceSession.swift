//
//  DeviceServiceSession.swift
//  MinimuxerCommon
//
//  Serializes lockdown/misagent sessions and retries only when the
//  socket was closed (BrokenPipe / reset). Never reports success without
//  the underlying operation succeeding.
//

import Foundation

public enum DeviceServiceSession {
    public static let maxAttempts = 3
    public static let defaultRetryDelayMs = [150, 400]
    public static let postCloseSettleMs = 80

    private static let lockdownLock = NSLock()
    private static let misagentLock = NSLock()

    public static func isTransientSocketFailure(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("broken pipe")
            || m.contains("brokenpipe")
            || m.contains("connection reset")
            || m.contains("connectionreset")
            || m.contains("connection aborted")
            || m.contains("connection closed")
            || m.contains("socket is closed")
            || m.contains("early eof")
            || m.contains("os error 32")
            || m.contains("os error 54")
            || m.contains("os error 104")
    }

    public static func isTransientSocketFailure(_ error: Error) -> Bool {
        let parts = [
            (error as? LocalizedError)?.errorDescription,
            error.localizedDescription,
            String(describing: error)
        ].compactMap { $0 }
        return parts.contains { isTransientSocketFailure($0) }
    }

    public static func withLockdownSession<T>(_ body: () throws -> T) throws -> T {
        lockdownLock.lock()
        defer { lockdownLock.unlock() }
        return try body()
    }

    public static func withMisagent<T>(step: String, _ body: () throws -> T) throws -> T {
        debugLog("[misagent] step=\(step) queue")
        misagentLock.lock()
        defer {
            if postCloseSettleMs > 0 {
                Thread.sleep(forTimeInterval: Double(postCloseSettleMs) / 1000.0)
            }
            misagentLock.unlock()
            debugLog("[misagent] step=\(step) end")
        }
        debugLog("[misagent] step=\(step) begin")
        return try body()
    }

    /// Finite retry of a closed channel. Non-transient errors fail immediately.
    public static func retryTransient<T>(
        operation: String,
        maxAttempts: Int = maxAttempts,
        delayMs: [Int] = defaultRetryDelayMs,
        isTransient: (Error) -> Bool = { isTransientSocketFailure($0) },
        sleeper: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        _ body: () throws -> T
    ) throws -> T {
        let attempts = max(1, min(maxAttempts, 5))
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                debugLog("[session] \(operation) attempt \(attempt)/\(attempts)")
                let value = try body()
                if attempt > 1 {
                    debugLog("[session] \(operation) recovered on attempt \(attempt)")
                }
                return value
            } catch {
                lastError = error
                let transient = isTransient(error)
                debugLog("[session] \(operation) attempt \(attempt)/\(attempts) failed transient=\(transient) error=\(error.localizedDescription)")
                if !transient || attempt == attempts {
                    throw error
                }
                let delayIndex = attempt - 1
                let ms = delayIndex < delayMs.count ? delayMs[delayIndex] : (delayMs.last ?? 0)
                if ms > 0 {
                    sleeper(Double(ms) / 1000.0)
                }
            }
        }
        throw lastError ?? NSError(
            domain: "DeviceServiceSession",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "\(operation) exhausted retries"]
        )
    }
}
