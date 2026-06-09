import ArgumentParser
import Foundation
import SMCKit

/// Set from the `SIGINT` handler (Ctrl+C). File-scope so the handler — which must
/// be a non-capturing C function — can flag the render loop to stop. `sig_atomic_t`
/// writes are async-signal-safe, so `nonisolated(unsafe)` is sound here.
private nonisolated(unsafe) var watchShouldStop: sig_atomic_t = 0

struct WatchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "watch",
        abstract: "Continuously display fan state, refreshing in place (like top)."
    )

    @Option(name: .long, help: "Refresh interval in seconds.")
    var interval: Double = 1.0

    func validate() throws {
        guard interval > 0 else {
            throw ValidationError("--interval must be greater than 0.")
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

        signal(SIGINT) { _ in watchShouldStop = 1 }

        // Hide the cursor while the live view is up; always restore it on exit
        // (Ctrl+C, error, or normal return) so the terminal is never left broken.
        write("\u{1B}[?25l")
        defer { write("\u{1B}[?25h\n") }

        let header = "macfanctl watch — every \(String(format: "%g", interval))s  (Ctrl+C to quit)"

        while watchShouldStop == 0 {
            let body: String
            do {
                body = renderFanTable(try smc.readFans())
            } catch {
                body = "Failed to read fans: \(error)"
            }

            // Clear screen + move cursor home, then redraw the frame in place.
            write("\u{1B}[2J\u{1B}[H\(header)\n\n\(body)\n")

            // Sleep in small slices so Ctrl+C is acted on promptly, not after a full interval.
            var elapsed = 0.0
            while elapsed < interval && watchShouldStop == 0 {
                Thread.sleep(forTimeInterval: 0.05)
                elapsed += 0.05
            }
        }
    }

    private func write(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }
}
