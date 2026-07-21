@testable import macfanctl
import XCTest

final class RaycastScriptInstallerTests: XCTestCase {
    func testCatalogMatchesTopLevelRaycastScripts() throws {
        let expectedFilenames: Set<String> = [
            "fan-auto.sh",
            "fan-max.sh",
            "fan-rpm.sh",
            "fan-status.sh",
        ]
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        XCTAssertEqual(RaycastScripts.all.count, 4)
        XCTAssertEqual(Set(RaycastScripts.all.map(\.filename)), expectedFilenames)

        for script in RaycastScripts.all {
            let source = repositoryRoot
                .appendingPathComponent("raycast", isDirectory: true)
                .appendingPathComponent(script.filename)
            XCTAssertEqual(Data(script.contents.utf8), try Data(contentsOf: source), script.filename)
        }
    }

    func testDestinationDirectoryDefaultsToRaycastScriptInHomeDirectory() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        XCTAssertEqual(
            RaycastScriptInstaller.destinationDirectory(homeDirectory: home).path,
            "/Users/tester/raycast-script"
        )
    }

    func testDestinationDirectoryUsesCustomPathExactly() {
        XCTAssertEqual(
            RaycastScriptInstaller.destinationDirectory(directoryPath: "/Users/tester/Documents").path,
            "/Users/tester/Documents"
        )
    }

    func testInstallWritesEveryManagedScriptAsExecutable() throws {
        let root = try temporaryDirectory()
        let destination = root.appendingPathComponent("raycast", isDirectory: true)
        let installed = try RaycastScriptInstaller().install(RaycastScripts.all, at: destination)

        XCTAssertEqual(Set(installed.map(\.lastPathComponent)), Set(RaycastScripts.all.map(\.filename)))
        for script in RaycastScripts.all {
            let file = destination.appendingPathComponent(script.filename)
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), script.contents)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
        }
    }

    func testInstallReplacesManagedFilesAndPreservesUnrelatedFiles() throws {
        let root = try temporaryDirectory()
        let destination = root.appendingPathComponent("raycast", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "stale".write(to: destination.appendingPathComponent("fan-auto.sh"), atomically: true, encoding: .utf8)
        try "keep".write(to: destination.appendingPathComponent("personal.sh"), atomically: true, encoding: .utf8)

        _ = try RaycastScriptInstaller().install(RaycastScripts.all, at: destination)
        _ = try RaycastScriptInstaller().install(RaycastScripts.all, at: destination)

        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("fan-auto.sh"), encoding: .utf8),
            RaycastScripts.all.first { $0.filename == "fan-auto.sh" }?.contents
        )
        XCTAssertEqual(
            try String(contentsOf: destination.appendingPathComponent("personal.sh"), encoding: .utf8),
            "keep"
        )
    }

    func testManagedScriptContentsEndWithExactlyOneNewline() {
        for script in RaycastScripts.all {
            let trailingNewlineCount = script.contents.reversed().prefix(while: { $0 == "\n" }).count
            XCTAssertEqual(trailingNewlineCount, 1, "\(script.filename) should end with exactly one newline")
        }
    }

    func testInstallReportsDirectoryCreationFailure() throws {
        let root = try temporaryDirectory()
        let blocked = root.appendingPathComponent("blocked")
        try Data().write(to: blocked)

        XCTAssertThrowsError(
            try RaycastScriptInstaller().install(
                RaycastScripts.all,
                at: blocked.appendingPathComponent("raycast")
            )
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }
}
