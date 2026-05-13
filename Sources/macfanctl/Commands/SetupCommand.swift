import ArgumentParser
import Darwin
import Foundation

struct SetupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Install or remove a NOPASSWD sudoers rule for this binary. Requires sudo."
    )

    @Flag(name: .long, help: "Remove the sudoers rule instead of installing it.")
    var uninstall: Bool = false

    private static let sudoersPath = "/etc/sudoers.d/macfanctl"

    func run() throws {
        guard geteuid() == 0 else {
            FileHandle.standardError.write(Data(
                "setup requires root. Run: sudo macfanctl setup\n".utf8
            ))
            throw ExitCode(3)
        }

        if uninstall {
            try runUninstall()
        } else {
            try runInstall()
        }
    }

    private func runInstall() throws {
        guard let user = ProcessInfo.processInfo.environment["SUDO_USER"], !user.isEmpty else {
            FileHandle.standardError.write(Data(
                "Could not determine invoking user (SUDO_USER unset). Run via: sudo macfanctl setup\n".utf8
            ))
            throw ExitCode(2)
        }

        let binPath = Self.executablePath()
        let rule = "\(user) ALL=(root) NOPASSWD: \(binPath)\n"

        try rule.write(toFile: Self.sudoersPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o440)],
            ofItemAtPath: Self.sudoersPath
        )

        try Self.verifyWithVisudo()

        print("Installed: \(Self.sudoersPath)")
        print("  \(rule.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    private func runUninstall() throws {
        if FileManager.default.fileExists(atPath: Self.sudoersPath) {
            try FileManager.default.removeItem(atPath: Self.sudoersPath)
            print("Removed: \(Self.sudoersPath)")
        } else {
            print("\(Self.sudoersPath) not present.")
        }
    }

    private static func verifyWithVisudo() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/visudo")
        process.arguments = ["-c", "-f", sudoersPath]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(atPath: sudoersPath)
            let output = String(
                data: pipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            FileHandle.standardError.write(Data(
                "visudo validation failed; sudoers file removed.\n\(output)".utf8
            ))
            throw ExitCode(2)
        }
    }

    private static func executablePath() -> String {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buf = [UInt8](repeating: 0, count: Int(size))
        _ = buf.withUnsafeMutableBufferPointer { ptr in
            _NSGetExecutablePath(ptr.baseAddress.map { UnsafeMutableRawPointer($0).assumingMemoryBound(to: CChar.self) }, &size)
        }
        if let nullIndex = buf.firstIndex(of: 0) {
            buf = Array(buf.prefix(nullIndex))
        }
        return String(decoding: buf, as: UTF8.self)
    }
}
