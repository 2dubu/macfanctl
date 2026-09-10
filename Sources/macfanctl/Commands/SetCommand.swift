import ArgumentParser
import Foundation
import SMCKit

struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set fan target RPM. Defaults to all fans. Requires root (sudo)."
    )

    @Argument(help: "Target RPM.")
    var rpm: Int

    @Option(name: .long, help: "Fan index (0-based). Omit to apply to all fans.")
    var fan: Int?

    func validate() throws {
        if rpm < 0 {
            throw ValidationError("RPM must be non-negative.")
        }
    }

    func run() throws {
        try FanControlConflict.check()

        let smc: SMC
        do {
            smc = try SMC()
        } catch {
            FileHandle.standardError.write(Data("Failed to open SMC: \(error)\n".utf8))
            throw ExitCode(2)
        }

        let targets: [Int]
        if let fan {
            targets = [fan]
        } else {
            let count = (try? smc.read(.fanCount).ui8).map(Int.init) ?? 0
            targets = Array(0..<count)
        }

        // Validate against hardware max for each target fan. Reject (do not clamp)
        // so the user knows their requested value didn't reach hardware.
        for index in targets {
            let max = (try? smc.read(.fanMax(index)).numeric).flatMap { $0 }.map(Int.init) ?? 0
            if max > 0 && rpm > max {
                FileHandle.standardError.write(Data(
                    "RPM \(rpm) exceeds fan \(index) max (\(max)). Use `macfanctl max` to set to hardware max.\n".utf8
                ))
                throw ExitCode(64)
            }
        }

        for index in targets {
            do {
                try smc.setFanTarget(index: index, rpm: rpm)
                print("Fan \(index): \(rpm) RPM")
            } catch SMCError.permissionDenied {
                FileHandle.standardError.write(Data("\(SMCError.permissionDenied)\n".utf8))
                throw ExitCode(3)
            } catch {
                FileHandle.standardError.write(Data("Fan \(index): \(error)\n".utf8))
                throw ExitCode(2)
            }
        }
    }
}
