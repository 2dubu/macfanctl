import Foundation

public struct SMCKey: Hashable, Sendable, CustomStringConvertible {
    public let raw: UInt32

    public init(_ string: String) {
        precondition(string.utf8.count == 4, "SMC key must be exactly 4 ASCII characters, got '\(string)'")
        var raw: UInt32 = 0
        for byte in string.utf8 {
            raw = (raw << 8) | UInt32(byte)
        }
        self.raw = raw
    }

    public init(raw: UInt32) {
        self.raw = raw
    }

    public var stringValue: String {
        let bytes: [UInt8] = [
            UInt8((raw >> 24) & 0xFF),
            UInt8((raw >> 16) & 0xFF),
            UInt8((raw >> 8) & 0xFF),
            UInt8(raw & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    public var description: String { stringValue }
}

public extension SMCKey {
    static let fanCount = SMCKey("FNum")

    /// Global fan unlock flag (`Ftst`). Writing `1` lets manual-mode writes through
    /// on generations that block them in System Mode (M4). Absent on M1/M5.
    static let fanTest = SMCKey("Ftst")

    static func fanActual(_ index: Int) -> SMCKey {
        precondition((0...9).contains(index), "Fan index out of range for 4-char SMC key: \(index)")
        return SMCKey("F\(index)Ac")
    }

    static func fanMin(_ index: Int) -> SMCKey {
        precondition((0...9).contains(index), "Fan index out of range for 4-char SMC key: \(index)")
        return SMCKey("F\(index)Mn")
    }

    static func fanMax(_ index: Int) -> SMCKey {
        precondition((0...9).contains(index), "Fan index out of range for 4-char SMC key: \(index)")
        return SMCKey("F\(index)Mx")
    }

    static func fanTarget(_ index: Int) -> SMCKey {
        precondition((0...9).contains(index), "Fan index out of range for 4-char SMC key: \(index)")
        return SMCKey("F\(index)Tg")
    }

    /// Fan mode key — `F%dMd` (uppercase, Intel/M4 convention).
    static func fanModeUppercase(_ index: Int) -> SMCKey {
        precondition((0...9).contains(index), "Fan index out of range for 4-char SMC key: \(index)")
        return SMCKey("F\(index)Md")
    }

    /// Fan mode key — `F%dmd` (lowercase, M5 convention).
    static func fanModeLowercase(_ index: Int) -> SMCKey {
        precondition((0...9).contains(index), "Fan index out of range for 4-char SMC key: \(index)")
        return SMCKey("F\(index)md")
    }
}
