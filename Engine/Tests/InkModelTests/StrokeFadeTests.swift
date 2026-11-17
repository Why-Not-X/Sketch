import XCTest
@testable import InkModel

final class StrokeFadeTests: XCTestCase {
    let fade = StrokeFade()

    func testWholeLineVisibleUntilTheDelay() {
        let p = fade.progress(age: 0.2)
        XCTAssertEqual(p, 0)
        for f: Float in [0, 0.5, 1] { XCTAssertEqual(fade.alpha(fraction: f, progress: p), 1, accuracy: 1e-6) }
    }

    func testTrailEatsTheStartFirst() {
        let p = fade.progress(age: fade.delay + fade.duration * 0.5)
        XCTAssertLessThan(fade.alpha(fraction: 0.1, progress: p), fade.alpha(fraction: 0.9, progress: p))
        XCTAssertEqual(fade.alpha(fraction: 0.05, progress: p), 0, accuracy: 1e-6, "the start is already gone")
        XCTAssertEqual(fade.alpha(fraction: 1, progress: p), 1, accuracy: 1e-6, "the end is still whole")
    }

    func testGoneAtTheEnd() {
        let age = fade.delay + fade.duration
        XCTAssertTrue(fade.isFinished(age: age))
        XCTAssertFalse(fade.isFinished(age: age - 0.01))
        for f: Float in [0, 0.5, 1] { XCTAssertEqual(fade.alpha(fraction: f, progress: 1), 0, accuracy: 1e-6) }
    }

    func testApplyUsesDistanceAlongTheLine() {
        let pts = (0...10).map { InkPoint(x: Float($0) * 0.01, y: 0, t: 0, width: 0.01) }
        let stroke = Stroke(id: 1, points: pts, isPencil: false)
        var v: [InkVertex] = []
        StrokeTessellator.append(pts, taperStart: true, taperEnd: true, taperLength: 0.02, taperMinFactor: 0.1,
                                 glowFactor: 3, into: &v)
        fade.apply(to: &v, range: 0..<v.count, length: stroke.length, progress: 0.5)
        XCTAssertEqual(stroke.length, 0.1, accuracy: 1e-6)
        XCTAssertLessThan(v.first!.alpha, v.last!.alpha)
    }
}
