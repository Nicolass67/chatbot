//
//  DeviceServiceSessionTests.swift
//  MinimuxerCommonTests
//

import XCTest
@testable import MinimuxerCommon

private struct FakeSocketError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class DeviceServiceSessionTests: XCTestCase {
    func testBrokenPipeIsTransient() {
        XCTAssertTrue(DeviceServiceSession.isTransientSocketFailure("Failed to connect to misagent, error: (Socket: BrokenPipe)"))
        XCTAssertTrue(DeviceServiceSession.isTransientSocketFailure(FakeSocketError(message: "os error 32")))
        XCTAssertTrue(DeviceServiceSession.isTransientSocketFailure(FakeSocketError(message: "Connection reset by peer")))
    }

    func testInvalidProfileIsNotTransient() {
        XCTAssertFalse(DeviceServiceSession.isTransientSocketFailure("Failed to install profile, error: (MisagentFailure)"))
        XCTAssertFalse(DeviceServiceSession.isTransientSocketFailure(FakeSocketError(message: "Invalid pairing file")))
    }

    func testRetryRecoversAfterTransientThenSucceeds() throws {
        var calls = 0
        let value = try DeviceServiceSession.retryTransient(
            operation: "misagent.install",
            maxAttempts: 3,
            delayMs: [0, 0],
            sleeper: { _ in }
        ) { () -> String in
            calls += 1
            if calls < 2 {
                throw FakeSocketError(message: "Socket BrokenPipe")
            }
            return "installed"
        }
        XCTAssertEqual(value, "installed")
        XCTAssertEqual(calls, 2)
    }

    func testRetryStopsAtMaxAttempts() {
        var calls = 0
        XCTAssertThrowsError(
            try DeviceServiceSession.retryTransient(
                operation: "misagent.connect",
                maxAttempts: 3,
                delayMs: [0, 0],
                sleeper: { _ in }
            ) { () -> Void in
                calls += 1
                throw FakeSocketError(message: "BrokenPipe")
            }
        )
        XCTAssertEqual(calls, 3)
    }

    func testNonTransientDoesNotRetry() {
        var calls = 0
        XCTAssertThrowsError(
            try DeviceServiceSession.retryTransient(
                operation: "misagent.install",
                maxAttempts: 3,
                delayMs: [0, 0],
                sleeper: { _ in }
            ) { () -> Void in
                calls += 1
                throw FakeSocketError(message: "MisagentFailure")
            }
        )
        XCTAssertEqual(calls, 1)
    }

    func testMisagentLockSerializesOverlappingSteps() {
        let occupancy = NSLock()
        var inCritical = 0
        var maxInCritical = 0
        let group = DispatchGroup()
        for _ in 0..<4 {
            group.enter()
            DispatchQueue.global().async {
                try? DeviceServiceSession.withMisagent(step: "install") {
                    occupancy.lock()
                    inCritical += 1
                    maxInCritical = max(maxInCritical, inCritical)
                    occupancy.unlock()
                    Thread.sleep(forTimeInterval: 0.02)
                    occupancy.lock()
                    inCritical -= 1
                    occupancy.unlock()
                }
                group.leave()
            }
        }
        group.wait()
        XCTAssertEqual(maxInCritical, 1)
    }
}
