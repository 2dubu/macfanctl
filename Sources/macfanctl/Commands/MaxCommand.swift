import ArgumentParser
import Foundation
import SMCKit

struct MaxCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "max",
        abstract: "Set fan(s) to hardware maximum RPM. Requires root (sudo)."
    )

    @Option(name: .long, help: "Fan index (0-based). Omit to apply to all fans.")
    var fan: Int?

    func run() throws {
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

        for index in targets {
            let max: Int
            do {
                max = (try smc.read(.fanMax(index)).numeric).map(Int.init) ?? 0
            } catch {
                FileHandle.standardError.write(Data("Fan \(index): could not read max RPM: \(error)\n".utf8))
                throw ExitCode(2)
            }
            guard max > 0 else {
                FileHandle.standardError.write(Data("Fan \(index): hardware max is 0; refusing to set.\n".utf8))
                throw ExitCode(2)
            }

            do {
                try smc.setFanTarget(index: index, rpm: max)
                print("Fan \(index): \(max) RPM (max)")
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
