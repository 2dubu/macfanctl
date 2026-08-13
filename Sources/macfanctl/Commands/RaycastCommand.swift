import ArgumentParser
import Darwin
import Foundation

struct RaycastCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "raycast",
        abstract: "Manage Raycast script commands.",
        subcommands: [RaycastSetupCommand.self]
    )
}

struct RaycastSetupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Install macfanctl Raycast script commands."
    )

    @Option(
        name: .long,
        help: "Directory where the Raycast scripts are installed."
    )
    var directory: String?

    func run() throws {
        try Self.validateEffectiveUserID(geteuid())

        let destination = RaycastScriptInstaller.destinationDirectory(directoryPath: directory)
        let installed = try RaycastScriptInstaller().install(RaycastScripts.all, at: destination)
        print("Installed \(installed.count) Raycast commands:")
        print("  \(destination.path)")
        print("In Raycast, choose + → Add Script Directory and select this folder.")

        Self.open([destination.path])
        Self.open([
            "-b", "com.raycast.macos",
            "raycast://extensions/raycast/raycast/open-preferences-extensions",
        ])
    }

    static func validateEffectiveUserID(_ userID: uid_t) throws {
        if userID == 0 {
            throw ValidationError(
                "Raycast setup must run without sudo. Run: macfanctl raycast setup"
            )
        }
    }

    private static func open(_ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                warning("/usr/bin/open exited with status \(process.terminationStatus).")
            }
        } catch {
            warning("Could not open \(arguments.last ?? "target"): \(error)")
        }
    }

    private static func warning(_ message: String) {
        FileHandle.standardError.write(Data("Warning: \(message)\n".utf8))
    }
}
