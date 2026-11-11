import CoreGraphics
import XCTest
@testable import YomiView

final class CanvasLayoutTests: XCTestCase {
    private let page = CGSize(width: 1000, height: 2000)

    func testFrameUniformHeight() {
        let (sizes, frame) = CanvasLayout.frame(pageSizes: [CGSize(width: 500, height: 1000), CGSize(width: 1000, height: 2000)])
        XCTAssertEqual(sizes, [CGSize(width: 1000, height: 2000), CGSize(width: 1000, height: 2000)])
        XCTAssertEqual(frame, CGSize(width: 2000, height: 2000))
    }

    func testStretchModes() {
        let canvas = CGSize(width: 800, height: 600)
        func scale(_ mode: PageStretchMode) -> CGFloat {
            CanvasLayout.stretchScale(mode: mode, frame: page, angle: 0, canvas: canvas)
        }
        XCTAssertEqual(scale(.none), 1)
        XCTAssertEqual(scale(.uniform), 0.3, accuracy: 1e-9)
        XCTAssertEqual(scale(.uniformToFill), 0.8, accuracy: 1e-9)
        XCTAssertEqual(scale(.uniformToHorizontal), 0.8, accuracy: 1e-9)
        XCTAssertEqual(scale(.uniformToVertical), 0.3, accuracy: 1e-9)
        XCTAssertEqual(scale(.uniformToSize), sqrt(480_000.0 / 2_000_000), accuracy: 1e-9)
    }

    func testAllowScaleUpAndDown() {
        let small = CGSize(width: 100, height: 100)
        let canvas = CGSize(width: 1000, height: 1000)
        XCTAssertEqual(CanvasLayout.stretchScale(mode: .uniform, frame: small, angle: 0, canvas: canvas), 10)
        XCTAssertEqual(CanvasLayout.stretchScale(mode: .uniform, frame: small, angle: 0, canvas: canvas, allowScaleUp: false), 1)
        XCTAssertEqual(CanvasLayout.stretchScale(mode: .uniform, frame: page, angle: 0, canvas: canvas, allowScaleDown: false), 1)
    }

    func testRotatedBounds() {
        let rotated = CanvasLayout.rotatedBounds(page, angle: 90)
        XCTAssertEqual(rotated.width, 2000, accuracy: 1e-9)
        XCTAssertEqual(rotated.height, 1000, accuracy: 1e-9)
        let diagonal = CanvasLayout.rotatedBounds(CGSize(width: 100, height: 100), angle: 45)
        XCTAssertEqual(diagonal.width, 100 * sqrt(2), accuracy: 1e-9)
    }

    func testOriginOffsetDependsOnDirection() {
        let content = CGSize(width: 1200, height: 1600)
        let canvas = CGSize(width: 800, height: 1000)
        XCTAssertEqual(
            CanvasLayout.originOffset(content: content, canvas: canvas, origin: .start, direction: .rightToLeft),
            CGSize(width: -200, height: 300), "右開きは右上から"
        )
        XCTAssertEqual(
            CanvasLayout.originOffset(content: content, canvas: canvas, origin: .start, direction: .leftToRight),
            CGSize(width: 200, height: 300), "左開きは左上から"
        )
        XCTAssertEqual(
            CanvasLayout.originOffset(content: content, canvas: canvas, origin: .end, direction: .rightToLeft),
            CGSize(width: 200, height: -300)
        )
        XCTAssertEqual(
            CanvasLayout.originOffset(content: CGSize(width: 100, height: 100), canvas: canvas, origin: .start, direction: .rightToLeft),
            .zero, "収まる内容は中央"
        )
    }

    func testClampOffset() {
        let clamped = CanvasLayout.clampOffset(
            CGSize(width: 1000, height: -1000), content: CGSize(width: 1000, height: 500), canvas: CGSize(width: 800, height: 800)
        )
        XCTAssertEqual(clamped, CGSize(width: 100, height: 0))
    }
}
