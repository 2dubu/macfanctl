import Foundation

/// The fan-control transaction, separated from IOKit so write ordering and
/// failure handling can be verified without touching hardware.
internal struct FanControlOperations {
    let read: (SMCKey) throws -> SMCKeyData
    let write: (SMCKey, [UInt8]) throws -> Void
    let resolveModeKey: (Int) throws -> SMCKey

    func setTarget(
        index: Int,
        rpm: Int,
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws {
        let modeKey = try resolveModeKey(index)
        let targetKey = SMCKey.fanTarget(index)
        let target = try read(targetKey)
        let bytes: [UInt8]
        switch target.dataTypeString {
        case "flt ": bytes = SMCEncoder.flt(Float(rpm))
        case "fpe2": bytes = SMCEncoder.fpe2(rpm: rpm)
        default: throw SMCError.unsupportedDataType(targetKey, type: target.dataTypeString)
        }
        let previousMode = try readByte(modeKey)
        guard [0, 1, 3].contains(previousMode) else {
            throw StateError.unknownMode(modeKey, previousMode)
        }

        // A mode write can succeed while the global unlock is still disabled.
        // Establish the unlock first wherever the key is supported.
        let unlock = try ensureUnlock()
        var enteredManualMode = false
        do {
            do {
                try write(modeKey, [1])
            } catch SMCError.smcResult(0x82) {
                guard unlock != .unsupported else { throw SMCError.modeWriteRejected(modeKey) }
                let deadline = now() + 10
                while true {
                    do {
                        try write(modeKey, [1])
                        break
                    } catch SMCError.smcResult(0x82) {
                        if now() >= deadline { throw SMCError.modeUnlockTimedOut(modeKey) }
                        sleep(0.1)
                    }
                }
            }
            enteredManualMode = previousMode != 1
            try write(targetKey, bytes)
        } catch {
            let operationError = error
            if enteredManualMode {
                do {
                    try restoreAuto(modeKey: modeKey, now: now, sleep: sleep)
                } catch {
                    throw StateError.cleanupFailed(operation: operationError, cleanup: error)
                }
            }
            if unlock == .acquired {
                do {
                    try resetUnlock()
                } catch {
                    throw StateError.cleanupFailed(operation: operationError, cleanup: error)
                }
            }
            throw operationError
        }
    }

    /// Mode reads can lag a successful write. Write once, then wait for the fan
    /// to leave manual mode before allowing the shared unlock to be released.
    func restoreAuto(
        index: Int,
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) throws {
        try restoreAuto(modeKey: resolveModeKey(index), now: now, sleep: sleep)
    }

    private func restoreAuto(
        modeKey: SMCKey,
        now: () -> TimeInterval,
        sleep: (TimeInterval) -> Void
    ) throws {
        do {
            try write(modeKey, [0])
        } catch SMCError.smcResult(0x82) {
            // System Mode can reject even an auto write. Confirm it owns the
            // fan after the rejection; never skip the write on a stale pre-read.
            guard try readByte(modeKey) == 3 else { throw SMCError.smcResult(0x82) }
            return
        }
        let deadline = now() + 10
        while true {
            let mode = try readByte(modeKey)
            if mode == 0 || mode == 3 { return }
            guard mode == 1 else { throw StateError.unknownMode(modeKey, mode) }
            if now() >= deadline { throw StateError.autoRestoreTimedOut(modeKey) }
            sleep(0.1)
        }
    }

    /// Ftst is shared by all fans. A partial `auto` request must leave it set
    /// while another fan is manual; uncertain reads must also preserve it.
    func resetUnlock() throws {
        guard let flag = try optionalUnlock(), flag != 0 else { return }
        let count = try readByte(.fanCount)
        guard count <= 10 else { throw StateError.invalidFanCount(count) }
        for index in 0..<Int(count) {
            let key = try resolveModeKey(index)
            let mode = try readByte(key)
            if mode == 1 { return }
            guard mode == 0 || mode == 3 else { throw StateError.unknownMode(key, mode) }
        }
        try write(.fanTest, [0])
    }

    private enum UnlockState { case unsupported, existing, acquired }

    private func ensureUnlock() throws -> UnlockState {
        guard let flag = try optionalUnlock() else { return .unsupported }
        guard flag == 0 else { return .existing }
        try write(.fanTest, [1])
        return .acquired
    }

    private func optionalUnlock() throws -> UInt8? {
        do {
            let flag = try readByte(.fanTest, types: ["ui8 ", "flag"])
            guard flag <= 1 else { throw StateError.invalidUnlock(flag) }
            return flag
        } catch SMCError.smcResult(0x84) {
            // Key-not-found is the only evidence that this hardware lacks Ftst.
            return nil
        }
    }

    private func readByte(_ key: SMCKey, types: Set<String> = ["ui8 "]) throws -> UInt8 {
        let value = try read(key)
        guard types.contains(value.dataTypeString) else {
            throw SMCError.unsupportedDataType(key, type: value.dataTypeString)
        }
        guard let byte = value.ui8 else {
            throw SMCError.unexpectedDataSize(key, expected: 1, got: value.bytes.count)
        }
        return byte
    }

    enum StateError: Error, CustomStringConvertible {
        case invalidUnlock(UInt8)
        case invalidFanCount(UInt8)
        case unknownMode(SMCKey, UInt8)
        case autoRestoreTimedOut(SMCKey)
        case cleanupFailed(operation: any Error, cleanup: any Error)

        var description: String {
            switch self {
            case .invalidUnlock(let flag):
                return "Invalid Ftst flag \(flag); expected 0 or 1."
            case .invalidFanCount(let count):
                return "Invalid fan count \(count); preserving the global fan unlock."
            case .unknownMode(let key, let mode):
                return "Unknown fan mode \(mode) for \(key); preserving the global fan unlock."
            case .autoRestoreTimedOut(let key):
                return "Fan \(key) remained in manual mode for 10 seconds after the auto request; preserving the global fan unlock."
            case .cleanupFailed(let operation, let cleanup):
                return "\(operation) Failed to restore fan control after the operation failed: \(cleanup)"
            }
        }
    }
}
