import ArgumentParser
import Foundation
import SMCKit

/// Set from the `SIGINT` or `SIGTERM` handler. File-scope so the handler — which must
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

    @Flag(name: .long, help: "Write one JSON diagnostic sample per line, without terminal formatting.")
    var json = false

    func validate() throws {
        guard interval.isFinite, interval > 0 else {
            throw ValidationError("--interval must be finite and greater than 0.")
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

        watchShouldStop = 0
        let previousInterruptHandler = signal(SIGINT) { _ in watchShouldStop = 1 }
        let previousTerminateHandler = signal(SIGTERM) { _ in watchShouldStop = 1 }
        defer {
            signal(SIGINT, previousInterruptHandler)
            signal(SIGTERM, previousTerminateHandler)
        }

        // Hide the cursor while the live view is up; always restore it on exit
        // (Ctrl+C, error, or normal return) so the terminal is never left broken.
        if !json { write("\u{1B}[?25l") }
        defer { if !json { write("\u{1B}[?25h\n") } }

        let header = "macfanctl watch — every \(String(format: "%g", interval))s  (Ctrl+C to quit)"

        while watchShouldStop == 0 {
            if json {
                let snapshot = FanStateSnapshot.capture(read: smc.read)
                FileHandle.standardOutput.write(try snapshot.jsonLine())
            } else {
                let body: String
                do {
                    body = renderFanTable(try smc.readFans())
                } catch {
                    body = "Failed to read fans: \(error)"
                }

                // Clear screen + move cursor home, then redraw the frame in place.
                write("\u{1B}[2J\u{1B}[H\(header)\n\n\(body)\n")
            }

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
