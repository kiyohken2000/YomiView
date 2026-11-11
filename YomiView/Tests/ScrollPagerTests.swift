import XCTest
@testable import YomiView

final class ScrollPagerTests: XCTestCase {
    func testTrackpadGestureTurnsOnlyOnePage() {
        var pager = ScrollPager()
        XCTAssertNil(pager.handle(deltaY: -5, phase: .began, isMomentum: false, timestamp: 0))
        XCTAssertEqual(pager.handle(deltaY: -10, phase: .changed, isMomentum: false, timestamp: 0.01), .next)
        XCTAssertNil(pager.handle(deltaY: -30, phase: .changed, isMomentum: false, timestamp: 0.02))
        XCTAssertNil(pager.handle(deltaY: -30, phase: .changed, isMomentum: false, timestamp: 0.03))
        XCTAssertNil(pager.handle(deltaY: 0, phase: .ended, isMomentum: false, timestamp: 0.04))
    }

    func testMomentumScrollIsIgnored() {
        var pager = ScrollPager()
        XCTAssertNil(pager.handle(deltaY: -50, phase: .none, isMomentum: true, timestamp: 0))
        XCTAssertNil(pager.handle(deltaY: -50, phase: .none, isMomentum: true, timestamp: 1))
    }

    func testNextGestureTurnsAgain() {
        var pager = ScrollPager()
        _ = pager.handle(deltaY: -20, phase: .began, isMomentum: false, timestamp: 0)
        _ = pager.handle(deltaY: 0, phase: .ended, isMomentum: false, timestamp: 0.1)
        XCTAssertNil(pager.handle(deltaY: 3, phase: .began, isMomentum: false, timestamp: 0.5))
        XCTAssertEqual(pager.handle(deltaY: 10, phase: .changed, isMomentum: false, timestamp: 0.6), .previous)
    }

    func testSmallGestureDoesNotTurn() {
        var pager = ScrollPager()
        XCTAssertNil(pager.handle(deltaY: -3, phase: .began, isMomentum: false, timestamp: 0))
        XCTAssertNil(pager.handle(deltaY: -4, phase: .changed, isMomentum: false, timestamp: 0.1))
        XCTAssertNil(pager.handle(deltaY: 0, phase: .ended, isMomentum: false, timestamp: 0.2))
    }

    func testMouseWheelDirection() {
        var pager = ScrollPager()
        XCTAssertEqual(pager.handle(deltaY: -1, phase: .none, isMomentum: false, timestamp: 0), .next)
        XCTAssertEqual(pager.handle(deltaY: 1, phase: .none, isMomentum: false, timestamp: 1), .previous)
        XCTAssertNil(pager.handle(deltaY: 0, phase: .none, isMomentum: false, timestamp: 2))
    }

    func testFastWheelIsThrottled() {
        var pager = ScrollPager()
        XCTAssertEqual(pager.handle(deltaY: -1, phase: .none, isMomentum: false, timestamp: 0), .next)
        XCTAssertNil(pager.handle(deltaY: -1, phase: .none, isMomentum: false, timestamp: 0.05))
        XCTAssertNil(pager.handle(deltaY: -1, phase: .none, isMomentum: false, timestamp: 0.10))
        XCTAssertEqual(pager.handle(deltaY: -1, phase: .none, isMomentum: false, timestamp: 0.16), .next)
    }
}
