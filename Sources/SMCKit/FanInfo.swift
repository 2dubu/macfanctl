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
    /// Enable the global `Ftst` unlock when supported, switch the fan to manual
    /// mode, then write its target. A successful mode write alone does not
    /// establish that the unlock is active. This is a one-shot operation and
    /// does not reapply settings after another controller or firmware resets them.
    func setFanTarget(index: Int, rpm: Int) throws {
        try fanControlOperations.setTarget(index: index, rpm: rpm)
    }

    /// Release manual control by writing mode 0 once, then wait up to 10 seconds
    /// for readback to confirm the fan has left manual mode.
    func restoreFanAuto(index: Int) throws {
        try fanControlOperations.restoreAuto(index: index)
    }

    /// Release the global `Ftst` unlock only after confirming no fan is manual.
    /// A partial auto request leaves it intact for the remaining manual fans.
    /// Missing `Ftst` is a no-op; other read failures propagate without clearing it.
    func resetFanTestUnlock() throws {
        try fanControlOperations.resetUnlock()
    }

    private var fanControlOperations: FanControlOperations {
        FanControlOperations(read: read, write: write, resolveModeKey: resolveModeKey(forFan:))
    }
}
