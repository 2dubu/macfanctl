@testable import macfanctl
import XCTest

final class RaycastCommandTests: XCTestCase {
    func testRootInvocationIsRejected() {
        XCTAssertThrowsError(try RaycastSetupCommand.validateEffectiveUserID(0))
    }

    func testRegularUserInvocationIsAccepted() {
        XCTAssertNoThrow(try RaycastSetupCommand.validateEffectiveUserID(501))
    }
}
