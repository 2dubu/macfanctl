import Foundation

public enum SMCError: Error, CustomStringConvertible, Sendable {
    case serviceNotFound(String)
    case openFailed(Int32)
    case callFailed(Int32)
    case smcResult(UInt8)
    case unexpectedDataSize(SMCKey, expected: Int, got: Int)
    case permissionDenied
    case unsupportedDataType(SMCKey, type: String)
    case modeKeyNotFound(fanIndex: Int)
    case modeWriteRejected(SMCKey)
    case modeUnlockTimedOut(SMCKey)

    public var description: String {
        switch self {
        case .serviceNotFound(let name):
            return "IOKit service '\(name)' not found. SMC may not be available on this Mac."
        case .openFailed(let code):
            return "Failed to open SMC connection: 0x\(String(UInt32(bitPattern: code), radix: 16))"
        case .callFailed(let code):
            return "IOConnectCallStructMethod failed: 0x\(String(UInt32(bitPattern: code), radix: 16))"
        case .smcResult(let code):
            return "SMC returned non-zero result code: 0x\(String(code, radix: 16))"
        case .unexpectedDataSize(let key, let expected, let got):
            return "Key \(key) data size mismatch: expected \(expected) bytes, got \(got)"
        case .permissionDenied:
            return "Permission denied. SMC write requires root — run with sudo."
        case .unsupportedDataType(let key, let type):
            return "Key \(key) has unsupported data type '\(type)' for this operation"
        case .modeKeyNotFound(let fanIndex):
            return "No fan mode key found for fan \(fanIndex) (tried F\(fanIndex)Md and F\(fanIndex)md). Manual control may not be supported on this Mac."
        case .modeWriteRejected(let key):
            return "Firmware rejected the manual-mode write to \(key) (SMC 0x82, System Mode) and no `Ftst` unlock key is available on this Mac. Manual fan control may be unsupported here."
        case .modeUnlockTimedOut(let key):
            return "Firmware did not release System Mode for \(key) within the timeout after the `Ftst` unlock. Try again, or report this with `macfanctl list --debug` output."
        }
    }
}
