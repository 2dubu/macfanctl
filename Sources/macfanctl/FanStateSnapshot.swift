import Foundation
import SMCKit

/// A read-only diagnostic sample. Missing or invalid readings stay null and carry
/// a key-specific error, so a failed SMC read cannot be mistaken for zero RPM.
struct FanStateSnapshot: Encodable {
    struct Fan: Encodable {
        let index: Int
        let actualRPM: Double?
        let targetRPM: Double?
        let modeBytes: [String: [UInt8]]

        enum CodingKeys: String, CodingKey {
            case index, actualRPM, targetRPM, modeBytes
        }

        func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(index, forKey: .index)
            try values.encode(actualRPM, forKey: .actualRPM)
            try values.encode(targetRPM, forKey: .targetRPM)
            try values.encode(modeBytes, forKey: .modeBytes)
        }
    }

    let timestamp: String
    let fanCount: Int?
    let fans: [Fan]
    let ftstBytes: [UInt8]?
    let readErrors: [String: String]

    enum CodingKeys: String, CodingKey {
        case timestamp, fanCount, fans, ftstBytes, readErrors
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(timestamp, forKey: .timestamp)
        try values.encode(fanCount, forKey: .fanCount)
        try values.encode(fans, forKey: .fans)
        try values.encode(ftstBytes, forKey: .ftstBytes)
        try values.encode(readErrors, forKey: .readErrors)
    }

    static func capture(
        at date: Date = Date(),
        read: (SMCKey) throws -> SMCKeyData
    ) -> FanStateSnapshot {
        var errors: [String: String] = [:]

        func readValue(_ key: SMCKey) -> SMCKeyData? {
            do {
                return try read(key)
            } catch {
                errors[key.stringValue] = String(describing: error)
                return nil
            }
        }

        func readRPM(_ key: SMCKey) -> Double? {
            guard let value = readValue(key) else { return nil }
            guard let rpm = value.numeric, rpm.isFinite else {
                errors[key.stringValue] = "Invalid or non-finite numeric value (type: \(value.dataTypeString))."
                return nil
            }
            return rpm
        }

        var count: Int?
        if let value = readValue(.fanCount) {
            if let byte = value.ui8, byte <= 10 {
                count = Int(byte)
            } else {
                errors[SMCKey.fanCount.stringValue] = "Invalid fan count; expected one byte in 0...10."
            }
        }

        let ftst = readValue(.fanTest)?.bytes
        let fans = (0..<(count ?? 0)).map { index in
            var modes: [String: [UInt8]] = [:]
            for key in [SMCKey.fanModeUppercase(index), .fanModeLowercase(index)] {
                if let value = readValue(key) {
                    modes[key.stringValue] = value.bytes
                }
            }
            return Fan(
                index: index,
                actualRPM: readRPM(.fanActual(index)),
                targetRPM: readRPM(.fanTarget(index)),
                modeBytes: modes
            )
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return FanStateSnapshot(
            timestamp: formatter.string(from: date),
            fanCount: count,
            fans: fans,
            ftstBytes: ftst,
            readErrors: errors
        )
    }

    func jsonLine() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }
}
