import Foundation

public struct FanInfo: Sendable, Codable, Equatable {
    public let index: Int
    public let actualRPM: Int
    public let minRPM: Int
    public let maxRPM: Int
    public let targetRPM: Int

    public init(index: Int, actualRPM: Int, minRPM: Int, maxRPM: Int, targetRPM: Int) {
        self.index = index
        self.actualRPM = actualRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.targetRPM = targetRPM
    }
}

public extension SMC {
    /// Read the fan count from `FNum`, then read each fan's actual/min/max/target.
    /// Individual key failures are swallowed (returns 0 for the missing field) so a partial
    /// SMC response on Apple Silicon still produces useful output.
    func readFans() throws -> [FanInfo] {
        let countData = try read(.fanCount)
        let count = Int(countData.ui8 ?? 0)
        guard count > 0 else { return [] }

        return (0..<count).map { i in
            FanInfo(
                index: i,
                actualRPM: rpm(for: SMCKey.fanActual(i)),
                minRPM:    rpm(for: SMCKey.fanMin(i)),
                maxRPM:    rpm(for: SMCKey.fanMax(i)),
                targetRPM: rpm(for: SMCKey.fanTarget(i))
            )
        }
    }

    private func rpm(for key: SMCKey) -> Int {
        do {
            return Int(try read(key).numeric ?? 0)
        } catch {
            return 0
        }
    }

    /// Set a fan's target RPM.
    ///
    /// On Apple Silicon, `thermalmonitord` enforces "System Mode" (mode 3) by
    /// default, which causes any write to `F%dTg` to be overwritten within
    /// milliseconds. The fix is to first switch the fan to manual mode by
    /// writing `1` to the fan mode key (`F%dMd` on M4, `F%dmd` on M5 — auto-detected),
    /// then write the target RPM to `F%dTg`.
    ///
    /// Note: firmware (`RTKit`) resets the unlock state on sleep/wake. For
    /// persistent control across sleep, a daemon must reapply mode=1 + target
    /// on wake.
    func setFanTarget(index: Int, rpm: Int) throws {
        let modeKey = try resolveModeKey(forFan: index)
        let targetKey = SMCKey.fanTarget(index)

        // 1. Switch the fan to manual mode (unlocks F%dTg writes from firmware override).
        try write(modeKey, bytes: [0x01])

        // 2. Write the target RPM in the appropriate encoding for this hardware.
        let probe = try read(targetKey)
        let bytes = try encode(rpm: rpm, forType: probe.dataTypeString, key: targetKey)
        try write(targetKey, bytes: bytes)
    }

    /// Release manual control by writing 0 to the fan mode key. `thermalmonitord`
    /// regains control and resumes managing the target on the next cycle (~250ms
    /// under thermal load, ~4000ms when idle).
    func restoreFanAuto(index: Int) throws {
        let modeKey = try resolveModeKey(forFan: index)
        try write(modeKey, bytes: [0x00])
    }

    private func encode(rpm: Int, forType type: String, key: SMCKey) throws -> [UInt8] {
        switch type {
        case "flt ": return SMCEncoder.flt(Float(rpm))
        case "fpe2": return SMCEncoder.fpe2(rpm: rpm)
        default:     throw SMCError.unsupportedDataType(key, type: type)
        }
    }
}
