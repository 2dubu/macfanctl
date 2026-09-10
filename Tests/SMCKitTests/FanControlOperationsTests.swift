@testable import SMCKit
import XCTest

final class FanControlOperationsTests: XCTestCase {
    private final class Hardware {
        var values: [SMCKey: SMCKeyData] = [:]
        var reads: [SMCKey] = []
        var writes: [(SMCKey, [UInt8])] = []
        var readFailure: [SMCKey: any Error] = [:]
        var readSequences: [SMCKey: [SMCKeyData]] = [:]
        var writeFailure: ((SMCKey, [UInt8]) -> (any Error)?)?

        init(flag: UInt8 = 0, firstMode: UInt8 = 0, secondMode: UInt8 = 0) {
            set(.fanCount, type: "ui8 ", bytes: [2])
            set(.fanTest, type: "ui8 ", bytes: [flag])
            set(.fanModeUppercase(0), type: "ui8 ", bytes: [firstMode])
            set(.fanModeUppercase(1), type: "ui8 ", bytes: [secondMode])
            set(.fanTarget(0), type: "flt ", bytes: SMCEncoder.flt(1500))
        }

        func set(_ key: SMCKey, type: String, bytes: [UInt8]) {
            values[key] = SMCKeyData(key: key, dataType: SMCKey(type).raw, bytes: bytes)
        }

        var operations: FanControlOperations {
            FanControlOperations(
                read: { key in
                    self.reads.append(key)
                    if let error = self.readFailure[key] { throw error }
                    if var sequence = self.readSequences[key], !sequence.isEmpty {
                        let value = sequence.removeFirst()
                        self.readSequences[key] = sequence
                        return value
                    }
                    guard let value = self.values[key] else { throw SMCError.smcResult(0x84) }
                    return value
                },
                write: { key, bytes in
                    self.writes.append((key, bytes))
                    if let error = self.writeFailure?(key, bytes) { throw error }
                    let type = self.values[key]?.dataTypeString ?? "ui8 "
                    self.set(key, type: type, bytes: bytes)
                },
                resolveModeKey: { .fanModeUppercase($0) }
            )
        }

        var writtenKeys: [SMCKey] { writes.map(\.0) }
        var flag: UInt8? { values[.fanTest]?.ui8 }

        func sequenceModes(_ modes: [UInt8]) {
            let key = SMCKey.fanModeUppercase(0)
            readSequences[key] = modes.map {
                SMCKeyData(key: key, dataType: SMCKey("ui8 ").raw, bytes: [$0])
            }
        }
    }

    func testUnlockPrecedesEvenAnImmediatelyAcceptedManualWrite() throws {
        let hardware = Hardware()
        try hardware.operations.setTarget(index: 0, rpm: 4000)
        XCTAssertEqual(hardware.writtenKeys, [.fanTest, .fanModeUppercase(0), .fanTarget(0)])
        XCTAssertEqual(hardware.writes[0].1, [1])
        XCTAssertEqual(hardware.writes[1].1, [1])
        XCTAssertEqual(hardware.writes[2].1, SMCEncoder.flt(4000))
    }

    func testExistingUnlockIsNotRewrittenAndFPE2TargetsStillWork() throws {
        let hardware = Hardware(flag: 1)
        hardware.set(.fanTarget(0), type: "fpe2", bytes: SMCEncoder.fpe2(rpm: 1500))
        try hardware.operations.setTarget(index: 0, rpm: 4000)
        XCTAssertEqual(hardware.writtenKeys, [.fanModeUppercase(0), .fanTarget(0)])
        XCTAssertEqual(hardware.writes.last?.1, SMCEncoder.fpe2(rpm: 4000))
    }

    func testOnlyMissingUnlockKeyPermitsDirectManualWrite() throws {
        let missing = Hardware()
        missing.values.removeValue(forKey: .fanTest)
        try missing.operations.setTarget(index: 0, rpm: 4000)
        XCTAssertEqual(missing.writtenKeys, [.fanModeUppercase(0), .fanTarget(0)])

        for error in [SMCError.permissionDenied, .smcResult(0x85), .callFailed(-1)] {
            let failed = Hardware()
            failed.readFailure[.fanTest] = error
            XCTAssertThrowsError(try failed.operations.setTarget(index: 0, rpm: 4000))
            XCTAssertTrue(failed.writes.isEmpty)
        }
    }

    func testUnlockFlagMustHaveABooleanTypeSizeAndValue() throws {
        for (type, bytes): (String, [UInt8]) in [("ui16", [0]), ("ui8 ", []), ("ui8 ", [0, 0]), ("ui8 ", [2])] {
            let hardware = Hardware()
            hardware.set(.fanTest, type: type, bytes: bytes)
            XCTAssertThrowsError(try hardware.operations.setTarget(index: 0, rpm: 4000))
            XCTAssertTrue(hardware.writes.isEmpty)
        }
        let flagType = Hardware()
        flagType.set(.fanTest, type: "flag", bytes: [0])
        XCTAssertNoThrow(try flagType.operations.setTarget(index: 0, rpm: 4000))
    }

    func testUnlockWriteFailureStopsBeforeManualOrTargetWrites() {
        let hardware = Hardware()
        hardware.writeFailure = { key, _ in key == .fanTest ? SMCError.permissionDenied : nil }
        XCTAssertThrowsError(try hardware.operations.setTarget(index: 0, rpm: 4000))
        XCTAssertEqual(hardware.writtenKeys, [.fanTest])
    }

    func testRejectedManualModeRetriesWithoutRewritingUnlock() throws {
        let hardware = Hardware()
        var attempts = 0
        hardware.writeFailure = { key, _ in
            guard key == .fanModeUppercase(0) else { return nil }
            attempts += 1
            return attempts <= 3 ? SMCError.smcResult(0x82) : nil
        }
        var time = 0.0
        try hardware.operations.setTarget(index: 0, rpm: 4000, now: { time }, sleep: { time += $0 })
        XCTAssertEqual(attempts, 4)
        XCTAssertEqual(hardware.writtenKeys.filter { $0 == .fanTest }.count, 1)
        XCTAssertEqual(hardware.writtenKeys.last, .fanTarget(0))
        XCTAssertEqual(time, 0.2, accuracy: 0.001)
    }

    func testMissingUnlockDoesNotEnterRetryLoopWhenModeIsRejected() {
        let hardware = Hardware()
        hardware.values.removeValue(forKey: .fanTest)
        hardware.writeFailure = { _, _ in SMCError.smcResult(0x82) }
        XCTAssertThrowsError(try hardware.operations.setTarget(index: 0, rpm: 4000, sleep: { _ in XCTFail("Unexpected retry") })) {
            guard case SMCError.modeWriteRejected = $0 else { return XCTFail("Wrong error: \($0)") }
        }
        XCTAssertEqual(hardware.writtenKeys, [.fanModeUppercase(0)])
    }

    func testTimeoutReleasesOnlyANewUnlockAndNeverWritesTarget() {
        for flag: UInt8 in [0, 1] {
            let hardware = Hardware(flag: flag)
            hardware.writeFailure = { key, _ in key == .fanModeUppercase(0) ? SMCError.smcResult(0x82) : nil }
            var time = 0.0
            XCTAssertThrowsError(try hardware.operations.setTarget(index: 0, rpm: 4000, now: { time }, sleep: { time += $0 })) {
                guard case SMCError.modeUnlockTimedOut = $0 else { return XCTFail("Wrong error: \($0)") }
            }
            XCTAssertGreaterThanOrEqual(time, 10)
            XCTAssertLessThan(time, 10.2)
            XCTAssertFalse(hardware.writtenKeys.contains(.fanTarget(0)))
            XCTAssertEqual(hardware.flag, flag)
        }
    }

    func testTargetFailureRestoresNewManualModeButPreservesExistingSession() {
        for initialMode: UInt8 in [0, 1, 3] {
            let hardware = Hardware(firstMode: initialMode)
            hardware.writeFailure = { key, _ in key == .fanTarget(0) ? SMCError.permissionDenied : nil }
            XCTAssertThrowsError(try hardware.operations.setTarget(index: 0, rpm: 4000))
            XCTAssertEqual(hardware.values[.fanModeUppercase(0)]?.ui8, initialMode == 1 ? 1 : 0)
            XCTAssertEqual(hardware.flag, initialMode == 1 ? 1 : 0)
            XCTAssertEqual(hardware.values[.fanTarget(0)]?.numeric, 1500)
        }
    }

    func testPartialAutoAndFailureCleanupPreserveAnotherManualFan() throws {
        let partialAuto = Hardware(flag: 1, secondMode: 1)
        try partialAuto.operations.resetUnlock()
        XCTAssertTrue(partialAuto.writes.isEmpty)

        let failedSet = Hardware(secondMode: 1)
        failedSet.writeFailure = { key, _ in key == .fanModeUppercase(0) ? SMCError.permissionDenied : nil }
        XCTAssertThrowsError(try failedSet.operations.setTarget(index: 0, rpm: 4000))
        XCTAssertEqual(failedSet.flag, 1)
        XCTAssertEqual(failedSet.writes.filter { $0.0 == .fanTest }.map(\.1), [[1]])
    }

    func testFullAutoReleasesUnlockAfterCheckingEveryFan() throws {
        let hardware = Hardware(flag: 1, secondMode: 3)
        try hardware.operations.resetUnlock()
        XCTAssertEqual(hardware.writtenKeys, [.fanTest])
        XCTAssertEqual(hardware.flag, 0)
        XCTAssertTrue(hardware.reads.contains(.fanModeUppercase(0)))
        XCTAssertTrue(hardware.reads.contains(.fanModeUppercase(1)))
    }

    func testUncertainFanStateCannotClearGlobalUnlock() {
        for key in [SMCKey.fanCount, .fanModeUppercase(0), .fanModeUppercase(1)] {
            let hardware = Hardware(flag: 1)
            hardware.readFailure[key] = SMCError.smcResult(0x84)
            XCTAssertThrowsError(try hardware.operations.resetUnlock())
            XCTAssertTrue(hardware.writes.isEmpty)
        }
        for (key, bytes): (SMCKey, [UInt8]) in [(.fanCount, [11]), (.fanModeUppercase(1), []), (.fanModeUppercase(1), [2])] {
            let hardware = Hardware(flag: 1)
            hardware.set(key, type: "ui8 ", bytes: bytes)
            XCTAssertThrowsError(try hardware.operations.resetUnlock())
            XCTAssertTrue(hardware.writes.isEmpty)
        }
    }

    func testCleanupReadFailurePreservesUnlockAndReportsBothFailures() {
        let hardware = Hardware()
        hardware.writeFailure = { key, _ in key == .fanModeUppercase(0) ? SMCError.permissionDenied : nil }
        hardware.readFailure[.fanCount] = SMCError.smcResult(0x85)
        XCTAssertThrowsError(try hardware.operations.setTarget(index: 0, rpm: 4000)) {
            guard case FanControlOperations.StateError.cleanupFailed = $0 else { return XCTFail("Wrong error: \($0)") }
            XCTAssertTrue(String(describing: $0).contains("Permission denied"))
            XCTAssertTrue(String(describing: $0).contains("0x85"))
        }
        XCTAssertEqual(hardware.flag, 1)
    }

    func testUnsupportedTargetTypeFailsBeforeAnyMutation() {
        let hardware = Hardware()
        hardware.set(.fanTarget(0), type: "ui8 ", bytes: [1])
        XCTAssertThrowsError(try hardware.operations.setTarget(index: 0, rpm: 4000))
        XCTAssertTrue(hardware.writes.isEmpty)
    }

    func testAutoWaitsForDelayedModeReadbackBeforeGlobalRelease() throws {
        let hardware = Hardware(flag: 1, firstMode: 1)
        hardware.sequenceModes([1, 1, 0])
        var time = 0.0
        try hardware.operations.restoreAuto(index: 0, now: { time }, sleep: { time += $0 })
        try hardware.operations.resetUnlock()
        XCTAssertEqual(hardware.writtenKeys, [.fanModeUppercase(0), .fanTest])
        XCTAssertEqual(hardware.writes.map(\.1), [[0], [0]])
        XCTAssertEqual(hardware.flag, 0)
        XCTAssertEqual(time, 0.2, accuracy: 0.001)
    }

    func testAutoTimeoutWritesModeOnlyOnceAndPreservesUnlock() {
        let hardware = Hardware(flag: 1, firstMode: 1)
        hardware.sequenceModes(Array(repeating: 1, count: 200))
        var time = 0.0
        XCTAssertThrowsError(try hardware.operations.restoreAuto(index: 0, now: { time }, sleep: { time += $0 })) {
            guard case FanControlOperations.StateError.autoRestoreTimedOut = $0 else { return XCTFail("Wrong error: \($0)") }
        }
        XCTAssertEqual(hardware.writtenKeys, [.fanModeUppercase(0)])
        XCTAssertEqual(hardware.writes[0].1, [0])
        XCTAssertEqual(hardware.flag, 1)
        XCTAssertGreaterThanOrEqual(time, 10)
        XCTAssertLessThan(time, 10.2)
    }

    func testSettledPartialAutoPreservesTheOtherManualFan() throws {
        let hardware = Hardware(flag: 1, firstMode: 1, secondMode: 1)
        hardware.sequenceModes([1, 0])
        var time = 0.0
        try hardware.operations.restoreAuto(index: 0, now: { time }, sleep: { time += $0 })
        try hardware.operations.resetUnlock()
        XCTAssertEqual(hardware.writtenKeys, [.fanModeUppercase(0)])
        XCTAssertEqual(hardware.flag, 1)
        XCTAssertEqual(hardware.values[.fanModeUppercase(1)]?.ui8, 1)
    }

    func testAutoReportsUnknownModesAndReadErrorsWithoutRetryingWrites() {
        let unknown = Hardware(flag: 1, firstMode: 1)
        unknown.sequenceModes([2])
        XCTAssertThrowsError(try unknown.operations.restoreAuto(index: 0, sleep: { _ in XCTFail("Unexpected wait") }))
        XCTAssertEqual(unknown.writtenKeys, [.fanModeUppercase(0)])
        XCTAssertEqual(unknown.flag, 1)

        let unreadable = Hardware(flag: 1, firstMode: 1)
        unreadable.readFailure[.fanModeUppercase(0)] = SMCError.smcResult(0x84)
        XCTAssertThrowsError(try unreadable.operations.restoreAuto(index: 0, sleep: { _ in XCTFail("Unexpected wait") }))
        XCTAssertEqual(unreadable.writtenKeys, [.fanModeUppercase(0)])
        XCTAssertEqual(unreadable.flag, 1)
    }

    func testTargetFailureRollbackAlsoWaitsBeforeGlobalRelease() {
        let hardware = Hardware()
        // The first read is preflight; the next three are rollback readback.
        hardware.sequenceModes([0, 1, 1, 0])
        hardware.writeFailure = { key, _ in key == .fanTarget(0) ? SMCError.permissionDenied : nil }
        var time = 0.0
        XCTAssertThrowsError(try hardware.operations.setTarget(index: 0, rpm: 4000, now: { time }, sleep: { time += $0 }))
        XCTAssertEqual(hardware.writtenKeys, [.fanTest, .fanModeUppercase(0), .fanTarget(0), .fanModeUppercase(0), .fanTest])
        XCTAssertEqual(hardware.flag, 0)
        XCTAssertEqual(time, 0.2, accuracy: 0.001)
    }

    func testAutoAcceptsRejectedWriteOnlyWhenSystemModeIsConfirmed() throws {
        let system = Hardware(flag: 1, firstMode: 3)
        system.writeFailure = { _, _ in SMCError.smcResult(0x82) }
        XCTAssertNoThrow(try system.operations.restoreAuto(index: 0, sleep: { _ in XCTFail("Unexpected wait") }))
        XCTAssertEqual(system.writtenKeys, [.fanModeUppercase(0)])

        for mode: UInt8 in [0, 1, 2] {
            let otherMode = Hardware(flag: 1, firstMode: mode)
            otherMode.writeFailure = { _, _ in SMCError.smcResult(0x82) }
            XCTAssertThrowsError(try otherMode.operations.restoreAuto(index: 0, sleep: { _ in XCTFail("Unexpected wait") })) {
                guard case SMCError.smcResult(0x82) = $0 else { return XCTFail("Wrong error: \($0)") }
            }
            XCTAssertEqual(otherMode.writtenKeys, [.fanModeUppercase(0)])
            XCTAssertEqual(otherMode.flag, 1)
        }
    }

    func testAutoRejectedWriteCannotAssumeSystemModeAfterAReadFailure() {
        let hardware = Hardware(flag: 1, firstMode: 3)
        hardware.writeFailure = { _, _ in SMCError.smcResult(0x82) }
        hardware.readFailure[.fanModeUppercase(0)] = SMCError.smcResult(0x85)
        XCTAssertThrowsError(try hardware.operations.restoreAuto(index: 0, sleep: { _ in XCTFail("Unexpected wait") })) {
            guard case SMCError.smcResult(0x85) = $0 else { return XCTFail("Wrong error: \($0)") }
        }
        XCTAssertEqual(hardware.writtenKeys, [.fanModeUppercase(0)])
        XCTAssertEqual(hardware.flag, 1)
    }
}
