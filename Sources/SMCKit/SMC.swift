import Foundation
import IOKit

// MARK: - SMCParamStruct (mirrors Apple's SMC kext IPC layout)

internal struct SMCKeyDataVersion {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

internal struct SMCKeyDataPLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

internal struct SMCKeyDataKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
    // C compilers pad this struct to 12 bytes for UInt32 alignment.
    // Swift doesn't add tail padding inside nested structs, so we add it explicitly
    // to match the AppleSMC kext's expected layout.
    var _pad: (UInt8, UInt8, UInt8) = (0, 0, 0)
}

internal struct SMCParamStruct {
    var key: UInt32 = 0
    var vers: SMCKeyDataVersion = SMCKeyDataVersion()
    var pLimitData: SMCKeyDataPLimitData = SMCKeyDataPLimitData()
    var keyInfo: SMCKeyDataKeyInfo = SMCKeyDataKeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}

// MARK: - SMC selectors

internal enum SMCSelector: UInt8 {
    case userClientOpen     = 0
    case userClientClose    = 1
    case handleYPCEvent     = 2
    case readKey            = 5
    case writeKey           = 6
    case getKeyFromIndex    = 8
    case getKeyInfo         = 9
}

// MARK: - SMC

public final class SMC {
    public enum ModeKeyCasing: Sendable {
        case uppercase  // F%dMd  (Intel / M4)
        case lowercase  // F%dmd  (M5)
    }

    private var connection: io_connect_t = 0
    private var modeKeyCasingCache: ModeKeyCasing?

    public init() throws {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else {
            throw SMCError.serviceNotFound("AppleSMC")
        }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard result == kIOReturnSuccess else {
            throw SMCError.openFailed(result)
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    // MARK: - Public API

    /// Read a single SMC key.
    public func read(_ key: SMCKey) throws -> SMCKeyData {
        let info = try fetchKeyInfo(key)

        var input = SMCParamStruct()
        input.key = key.raw
        input.keyInfo.dataSize = info.keyInfo.dataSize
        input.data8 = SMCSelector.readKey.rawValue

        let output = try call(input: input)
        let length = Int(info.keyInfo.dataSize)
        let bytes = extractBytes(from: output, length: length)

        return SMCKeyData(
            key: key,
            dataType: info.keyInfo.dataType,
            bytes: bytes
        )
    }

    /// Write bytes to an SMC key. Requires root privileges.
    /// The byte count must match the key's declared `dataSize` (queried via getKeyInfo first).
    public func write(_ key: SMCKey, bytes: [UInt8]) throws {
        let info = try fetchKeyInfo(key)
        let expected = Int(info.keyInfo.dataSize)
        guard bytes.count == expected else {
            throw SMCError.unexpectedDataSize(key, expected: expected, got: bytes.count)
        }

        var input = SMCParamStruct()
        input.key = key.raw
        input.keyInfo.dataSize = info.keyInfo.dataSize
        input.data8 = SMCSelector.writeKey.rawValue
        copyBytesIntoPayload(bytes, of: &input)

        _ = try call(input: input)
    }

    /// Resolve the fan mode key for a given index. On Apple Silicon the casing
    /// varies by chip generation: M4 uses `F%dMd`, M5 uses `F%dmd`. We probe
    /// uppercase first (broader compatibility), then lowercase. The result is
    /// cached on this `SMC` instance so subsequent fans skip the probe.
    public func resolveModeKey(forFan index: Int) throws -> SMCKey {
        if let cached = modeKeyCasingCache {
            return makeModeKey(casing: cached, index: index)
        }

        let upper = SMCKey.fanModeUppercase(index)
        if (try? fetchKeyInfo(upper)) != nil {
            modeKeyCasingCache = .uppercase
            return upper
        }

        let lower = SMCKey.fanModeLowercase(index)
        if (try? fetchKeyInfo(lower)) != nil {
            modeKeyCasingCache = .lowercase
            return lower
        }

        throw SMCError.modeKeyNotFound(fanIndex: index)
    }

    private func makeModeKey(casing: ModeKeyCasing, index: Int) -> SMCKey {
        switch casing {
        case .uppercase: return SMCKey.fanModeUppercase(index)
        case .lowercase: return SMCKey.fanModeLowercase(index)
        }
    }

    // MARK: - Internals

    private func fetchKeyInfo(_ key: SMCKey) throws -> SMCParamStruct {
        var input = SMCParamStruct()
        input.key = key.raw
        input.data8 = SMCSelector.getKeyInfo.rawValue
        return try call(input: input)
    }

    private func call(input: SMCParamStruct) throws -> SMCParamStruct {
        var inputCopy = input
        var output = SMCParamStruct()
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let result = withUnsafePointer(to: &inputCopy) { inputPtr -> Int32 in
            withUnsafeMutablePointer(to: &output) { outputPtr -> Int32 in
                IOConnectCallStructMethod(
                    connection,
                    UInt32(SMCSelector.handleYPCEvent.rawValue),
                    inputPtr,
                    inputSize,
                    outputPtr,
                    &outputSize
                )
            }
        }

        guard result == kIOReturnSuccess else {
            // 0xe00002e2 = kIOReturnNotPermitted — distinct error for clearer messages.
            if UInt32(bitPattern: result) == 0xE00002E2 {
                throw SMCError.permissionDenied
            }
            throw SMCError.callFailed(result)
        }
        guard output.result == 0 else {
            throw SMCError.smcResult(output.result)
        }
        return output
    }

    private func extractBytes(from output: SMCParamStruct, length: Int) -> [UInt8] {
        var paramCopy = output
        return withUnsafeBytes(of: &paramCopy.bytes) { raw -> [UInt8] in
            let clamped = min(length, raw.count)
            return Array(raw.prefix(clamped))
        }
    }

    private func copyBytesIntoPayload(_ source: [UInt8], of input: inout SMCParamStruct) {
        withUnsafeMutableBytes(of: &input.bytes) { dest in
            let limit = min(source.count, dest.count)
            for i in 0..<limit {
                dest[i] = source[i]
            }
        }
    }
}
