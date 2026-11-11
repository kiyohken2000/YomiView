import XCTest
@testable import YomiView

final class SmokeTests: XCTestCase {
    func testAppModuleLoads() {
        XCTAssertNotNil(Bundle(for: SmokeTests.self))
    }
}
