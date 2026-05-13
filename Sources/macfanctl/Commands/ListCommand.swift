import ArgumentParser
import Foundation
import SMCKit

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List detected fans and their current state."
    )

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json: Bool = false

    @Flag(name: .long, help: "Dump raw SMC data for each fan key.")
    var debug: Bool = false

    func run() throws {
        let smc: SMC
        do {
            smc = try SMC()
        } catch {
            FileHandle.standardError.write(Data("Failed to open SMC: \(error)\n".utf8))
            throw ExitCode(2)
        }

        if debug {
            try runDebug(smc: smc)
            return
        }

        let fans: [FanInfo]
        do {
            fans = try smc.readFans()
        } catch {
            FileHandle.standardError.write(Data("Failed to read fans: \(error)\n".utf8))
            throw ExitCode(2)
        }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(fans)
            print(String(decoding: data, as: UTF8.self))
            return
        }

        if fans.isEmpty {
            print("No fans detected (FNum returned 0).")
            return
        }

        print("Fan   Actual   Min    Max    Target")
        print("---   ------   ----   ----   ------")
        for fan in fans {
            print(String(
                format: "%-5d %-8d %-6d %-6d %-6d",
                fan.index, fan.actualRPM, fan.minRPM, fan.maxRPM, fan.targetRPM
            ))
        }
    }

    private func runDebug(smc: SMC) throws {
        print("=== SMC fan key dump ===\n")
        let count = (try? smc.read(.fanCount).ui8).map(Int.init) ?? 0
        print("FNum -> \(count) fan(s)\n")

        // Probe both the canonical Intel/SMC names and several Apple Silicon
        // alternatives commonly seen in the wild so we can confirm which
        // format M5 Max actually exposes.
        var candidates: [String] = []
        for i in 0..<max(count, 2) {
            candidates += [
                "F\(i)Ac", "F\(i)Mn", "F\(i)Mx", "F\(i)Tg",
                "F\(i)Sf", "F\(i)ID", "F\(i)Md",
            ]
        }

        for name in candidates {
            let key = SMCKey(name)
            do {
                let data = try smc.read(key)
                let hex = data.bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
                let fpe2 = data.fpe2.map { String(format: "%.2f", $0) } ?? "-"
                let flt  = data.flt.map  { String(format: "%.2f", $0) } ?? "-"
                let ui16 = data.ui16.map { String($0) } ?? "-"
                print("\(name)  type=\(data.dataTypeString)  bytes=[\(hex)]  fpe2=\(fpe2)  flt=\(flt)  ui16=\(ui16)")
            } catch {
                print("\(name)  ERROR: \(error)")
            }
        }
    }
}
