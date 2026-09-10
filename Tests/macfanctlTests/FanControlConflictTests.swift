@testable import macfanctl
import XCTest

final class FanControlConflictTests: XCTestCase {
    func testExactControllerBundleIsRejectedWithQuitGuidance() {
        XCTAssertThrowsError(try FanControlConflict.check(inventory: {
            [.init(processID: 123, bundleIdentifier: "com.crystalidea.macsfancontrol")]
        })) { error in
            XCTAssertEqual(error as? FanControlConflict.CheckError, .controllerRunning(processID: 123))
            XCTAssertTrue(String(describing: error).contains("Quit Macs Fan Control"))
            XCTAssertTrue(String(describing: error).contains("macfanctl auto"))
        }
    }

    func testHelperAloneDoesNotBlockManualControl() {
        XCTAssertNoThrow(try FanControlConflict.check(inventory: {
            [.init(processID: 123, bundleIdentifier: "com.crystalidea.macsfancontrol.smcwrite")]
        }))
    }

    func testUnrelatedApplicationWithSamePIDDoesNotBlockManualControl() {
        XCTAssertNoThrow(try FanControlConflict.check(inventory: {
            [.init(processID: 123, bundleIdentifier: "org.example.another-app")]
        }))
    }

    func testSimilarBundleIdentifierDoesNotMatch() {
        XCTAssertNoThrow(try FanControlConflict.check(inventory: {
            [.init(processID: 456, bundleIdentifier: "com.crystalidea.macsfancontrol-other")]
        }))
    }

    func testNoRunningApplicationsDoesNotBlockManualControl() {
        XCTAssertNoThrow(try FanControlConflict.check(inventory: { [] }))
    }

    func testInventoryFailureRefusesToProceed() {
        struct InventoryFailure: Error {}
        XCTAssertThrowsError(try FanControlConflict.check(inventory: { throw InventoryFailure() })) { error in
            guard case .inventoryUnavailable = error as? FanControlConflict.CheckError else {
                return XCTFail("Expected an inventory failure, got \(error)")
            }
            XCTAssertTrue(String(describing: error).contains("No fan settings were changed"))
        }
    }

    func testRenamedAppIsIdentifiedByItsMainExecutableAndBundleIdentifier() throws {
        let executable = try appExecutable(named: "Renamed Controller", identifier: "com.crystalidea.macsfancontrol")
        XCTAssertEqual(
            FanControlConflict.application(processID: 321, executableURL: executable),
            .init(processID: 321, bundleIdentifier: "com.crystalidea.macsfancontrol")
        )
    }

    func testMatchingDisplayNameWithUnrelatedBundleIdentifierDoesNotBlock() throws {
        let executable = try appExecutable(named: "Macs Fan Control", identifier: "org.example.unrelated")
        let application = try XCTUnwrap(FanControlConflict.application(processID: 321, executableURL: executable))
        XCTAssertNoThrow(try FanControlConflict.check(inventory: { [application] }))
    }

    func testExtraExecutableInsideControllerBundleIsNotItsMainApplication() throws {
        let mainExecutable = try appExecutable(named: "Macs Fan Control", identifier: "com.crystalidea.macsfancontrol")
        let helper = mainExecutable.deletingLastPathComponent().appendingPathComponent("smcwrite")
        try Data().write(to: helper)

        XCTAssertNil(FanControlConflict.application(processID: 321, executableURL: helper))
    }

    func testStandaloneHelperIsNotAnApplication() {
        XCTAssertNil(FanControlConflict.application(
            processID: 321,
            executableURL: URL(fileURLWithPath: "/Library/PrivilegedHelperTools/com.crystalidea.macsfancontrol.smcwrite")
        ))
    }

    private func appExecutable(named name: String, identifier: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = root.appendingPathComponent("\(name).app")
        let contents = bundle.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        let metadata: [String: String] = [
            "CFBundleIdentifier": identifier,
            "CFBundleExecutable": "Controller",
            "CFBundlePackageType": "APPL",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        let executable = macOS.appendingPathComponent("Controller")
        try Data().write(to: executable)
        return executable
    }
}
