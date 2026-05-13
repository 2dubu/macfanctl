import ArgumentParser
import Foundation
import SMCKit

struct AutoCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "auto",
        abstract: "Restore automatic fan control. Requires root (sudo)."
    )

    @Option(name: .long, help: "Fan index (0-based). Omit to restore all fans.")
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
            do {
                try smc.restoreFanAuto(index: index)
                print("Fan \(index) -> auto (target cleared)")
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
