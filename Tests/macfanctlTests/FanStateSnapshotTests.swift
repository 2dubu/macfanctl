@testable import macfanctl
import SMCKit
import XCTest

final class FanStateSnapshotTests: XCTestCase {
    private enum ReadFailure: Error { case unavailable }

    private func value(_ key: String, type: String = "ui8 ", bytes: [UInt8]) -> SMCKeyData {
        SMCKeyData(key: SMCKey(key), dataType: SMCKey(type).raw, bytes: bytes)
    }

    private func capture(_ values: [String: SMCKeyData]) -> FanStateSnapshot {
        FanStateSnapshot.capture(at: Date(timeIntervalSince1970: 0)) { key in
            guard let value = values[key.stringValue] else { throw ReadFailure.unavailable }
            return value
        }
    }

    func testCapturesRawModesAndBothFanRPMEncodings() throws {
        let snapshot = capture([
            "FNum": value("FNum", bytes: [1]),
            "Ftst": value("Ftst", bytes: [0]),
            "F0Md": value("F0Md", bytes: [1]),
            "F0md": value("F0md", bytes: [0]),
            "F0Ac": value("F0Ac", type: "flt ", bytes: SMCEncoder.flt(3999.5)),
            "F0Tg": value("F0Tg", type: "fpe2", bytes: SMCEncoder.fpe2(rpm: 4000)),
        ])

        XCTAssertEqual(snapshot.timestamp, "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(snapshot.fanCount, 1)
        XCTAssertEqual(snapshot.ftstBytes, [0])
        let fan = try XCTUnwrap(snapshot.fans.first)
        XCTAssertEqual(fan.actualRPM, 3999.5)
        XCTAssertEqual(fan.targetRPM, 4000)
        XCTAssertEqual(fan.modeBytes, ["F0Md": [1], "F0md": [0]])
        XCTAssertTrue(snapshot.readErrors.isEmpty)
    }

    func testUnavailableReadingsStayNullAndRealZeroStaysZero() throws {
        let snapshot = capture([
            "FNum": value("FNum", bytes: [1]),
            "F0Md": value("F0Md", bytes: [0]),
            "F0Ac": value("F0Ac", type: "flt ", bytes: SMCEncoder.flt(0)),
        ])
        let fan = try XCTUnwrap(snapshot.fans.first)
        XCTAssertEqual(fan.actualRPM, 0)
        XCTAssertNil(fan.targetRPM)
        XCTAssertNil(snapshot.ftstBytes)
        XCTAssertEqual(fan.modeBytes, ["F0Md": [0]])
        XCTAssertEqual(Set(snapshot.readErrors.keys), ["Ftst", "F0md", "F0Tg"])

        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: snapshot.jsonLine()) as? [String: Any])
        let jsonFans = try XCTUnwrap(json["fans"] as? [[String: Any]])
        XCTAssertTrue(json["ftstBytes"] is NSNull)
        XCTAssertTrue(jsonFans[0]["targetRPM"] is NSNull)
        XCTAssertEqual(jsonFans[0]["actualRPM"] as? Double, 0)
    }

    func testNonFiniteAndMalformedNumericReadingsAreReported() throws {
        for bytes in [SMCEncoder.flt(.nan), SMCEncoder.flt(.infinity), SMCEncoder.flt(-.infinity), [0]] {
            let snapshot = capture([
                "FNum": value("FNum", bytes: [1]),
                "F0Ac": value("F0Ac", type: "flt ", bytes: bytes),
                "F0Tg": value("F0Tg", type: "ch8*", bytes: [0, 0, 0, 0]),
            ])
            XCTAssertNil(snapshot.fans[0].actualRPM)
            XCTAssertNil(snapshot.fans[0].targetRPM)
            XCTAssertNotNil(snapshot.readErrors["F0Ac"])
            XCTAssertNotNil(snapshot.readErrors["F0Tg"])
            XCTAssertNoThrow(try snapshot.jsonLine())
        }
    }

    func testMissingAndInvalidFanCountsDoNotProbeMadeUpFanKeys() {
        for countBytes: [UInt8]? in [nil, [], [1, 0], [11], [255]] {
            var reads: [String] = []
            let snapshot = FanStateSnapshot.capture { key in
                reads.append(key.stringValue)
                guard key == .fanCount, let countBytes else { throw ReadFailure.unavailable }
                return self.value("FNum", bytes: countBytes)
            }
            XCTAssertNil(snapshot.fanCount)
            XCTAssertTrue(snapshot.fans.isEmpty)
            XCTAssertNotNil(snapshot.readErrors["FNum"])
            XCTAssertEqual(reads, ["FNum", "Ftst"])
        }

        let noFans = capture(["FNum": value("FNum", bytes: [0])])
        XCTAssertEqual(noFans.fanCount, 0)
        XCTAssertTrue(noFans.fans.isEmpty)
        XCTAssertNil(noFans.readErrors["FNum"])
    }

    func testJSONOutputHasOneLineWithoutTerminalEscapes() throws {
        let snapshot = FanStateSnapshot.capture { _ in
            throw NSError(domain: "test\nnext line\u{1B}[2J", code: 1)
        }
        let data = try snapshot.jsonLine()
        XCTAssertEqual(data.filter { $0 == 0x0A }.count, 1)
        XCTAssertEqual(data.last, 0x0A)
        XCTAssertFalse(data.contains(0x1B))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }

    func testJSONFlagAndFinitePositiveIntervalValidation() throws {
        let command = try WatchCommand.parse(["--json", "--interval", "0.25"])
        XCTAssertTrue(command.json)
        XCTAssertEqual(command.interval, 0.25)
        XCTAssertFalse(try WatchCommand.parse([]).json)

        let invalidIntervals: [Double] = [0, -1, .nan, .infinity, -.infinity]
        for interval in invalidIntervals {
            var invalid = WatchCommand()
            invalid.interval = interval
            XCTAssertThrowsError(try invalid.validate())
        }
    }
}
