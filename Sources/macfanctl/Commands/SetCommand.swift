import ArgumentParser
import Foundation
import SMCKit

struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set fan target RPM. Requires root (sudo)."
    )

    @Option(name: .long, help: "Fan index (0-based). Omit with --all.")
    var fan: Int?

    @Flag(name: .long, help: "Apply to all fans.")
    var all: Bool = false

    @Option(name: .long, help: "Target RPM.")
    var rpm: Int

    func validate() throws {
        if all && fan != nil {
            throw ValidationError("--all and --fan are mutually exclusive.")
        }
        if !all && fan == nil {
            throw ValidationError("Specify either --fan <index> or --all.")
        }
        if rpm < 0 {
            throw ValidationError("RPM must be non-negative.")
        }
    }

    func run() throws {
        let smc: SMC
        do {
            smc = try SMC()
        } catch {
            FileHandle.standardError.write(Data("Failed to open SMC: \(error)\n".utf8))
            throw ExitCode(2)
        }

        let targets: [Int]
        if all {
            let count = (try? smc.read(.fanCount).ui8).map(Int.init) ?? 0
            targets = Array(0..<count)
        } else {
            targets = [fan!]
        }

        for index in targets {
            do {
                try smc.setFanTarget(index: index, rpm: rpm)
                print("Fan \(index) -> target \(rpm) RPM")
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
