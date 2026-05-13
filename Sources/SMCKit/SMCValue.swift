import Foundation

public struct SMCKeyData: Sendable {
    public let key: SMCKey
    public let dataType: UInt32
    public let bytes: [UInt8]

    public init(key: SMCKey, dataType: UInt32, bytes: [UInt8]) {
        self.key = key
        self.dataType = dataType
        self.bytes = bytes
    }

    public var dataTypeString: String {
        let bytes: [UInt8] = [
            UInt8((dataType >> 24) & 0xFF),
            UInt8((dataType >> 16) & 0xFF),
            UInt8((dataType >> 8) & 0xFF),
            UInt8(dataType & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}

// MARK: - Decoders

public extension SMCKeyData {
    /// Unsigned 8-bit integer.
    var ui8: UInt8? {
        guard bytes.count == 1 else { return nil }
        return bytes[0]
    }

    /// Big-endian unsigned 16-bit integer.
    var ui16: UInt16? {
        guard bytes.count == 2 else { return nil }
        return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    }

    /// Big-endian unsigned 32-bit integer.
    var ui32: UInt32? {
        guard bytes.count == 4 else { return nil }
        return (UInt32(bytes[0]) << 24)
             | (UInt32(bytes[1]) << 16)
             | (UInt32(bytes[2]) << 8)
             |  UInt32(bytes[3])
    }

    /// `fpe2` — 14-bit unsigned integer with 2 fractional bits, big-endian. Used for fan RPM.
    var fpe2: Double? {
        guard let raw = ui16 else { return nil }
        return Double(raw) / 4.0
    }

    /// `sp78` — signed 8.8 fixed point, big-endian. Used for many temperature sensors.
    var sp78: Double? {
        guard bytes.count == 2 else { return nil }
        let raw = (Int16(Int8(bitPattern: bytes[0])) << 8) | Int16(bytes[1])
        return Double(raw) / 256.0
    }

    /// IEEE 754 single-precision float, little-endian. Used by Apple Silicon `flt ` keys
    /// for fan RPM and many temperature sensors. (Intel SMC stored values big-endian;
    /// Apple Silicon stores them native — i.e. little-endian on arm64.)
    var flt: Float? {
        guard bytes.count == 4 else { return nil }
        let raw = (UInt32(bytes[3]) << 24)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[1]) << 8)
                |  UInt32(bytes[0])
        return Float(bitPattern: raw)
    }

    /// Convenience: return a numeric value for known fan/temperature data types.
    /// Picks the right decoder based on `dataTypeString` so callers don't have to.
    var numeric: Double? {
        switch dataTypeString {
        case "fpe2": return fpe2
        case "flt ": return flt.map(Double.init)
        case "sp78": return sp78
        case "ui8 ": return ui8.map(Double.init)
        case "ui16": return ui16.map(Double.init)
        case "ui32": return ui32.map(Double.init)
        default:     return nil
        }
    }
}

// MARK: - Encoders (for writes)

public enum SMCEncoder {
    /// Encode an IEEE 754 single-precision float as little-endian bytes (for `flt ` keys).
    public static func flt(_ value: Float) -> [UInt8] {
        let raw = value.bitPattern
        return [
            UInt8(raw & 0xFF),
            UInt8((raw >> 8) & 0xFF),
            UInt8((raw >> 16) & 0xFF),
            UInt8((raw >> 24) & 0xFF),
        ]
    }

    /// Encode a fan RPM as 14.2 unsigned fixed-point, big-endian (for Intel-era `fpe2` keys).
    public static func fpe2(rpm: Int) -> [UInt8] {
        let raw = UInt16(clamping: rpm * 4)
        return [
            UInt8(raw >> 8),
            UInt8(raw & 0xFF),
        ]
    }
}
