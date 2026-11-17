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

    func testUnravelStartsAtTouchAndWrapsAroundClosedShapes() {
        let ring = Stroke.circle(id: 1, centerX: 0.5, centerY: 0.5, radius: 0.1, width: 0.005)
        // Touch at angle 0, which is where the ring starts: both ends are next to it.
        let u = ShapeUnravel(stroke: ring, x: 0.6, y: 0.5)
        XCTAssertTrue(u.closed)
        XCTAssertEqual(u.distance(along: u.length), 0, accuracy: 0.002)
        XCTAssertEqual(u.reach, u.length / 2, accuracy: 1e-5)
        // Halfway through, the touch point is gone and the far side is still there.
        XCTAssertEqual(u.alpha(along: 0, progress: 0.5), 0, accuracy: 1e-5)
        XCTAssertEqual(u.alpha(along: u.length / 2, progress: 0.5), 1, accuracy: 1e-5)
        XCTAssertEqual(u.alpha(along: u.length / 2, progress: 1), 0, accuracy: 1e-5)
        XCTAssertEqual(u.alpha(along: u.length / 2, progress: 0), 1, accuracy: 1e-5)
    }

    func testUnravelOnOpenLineGoesBothWays() {
        let pts = (0...100).map { InkPoint(x: Float($0) / 100, y: 0.5, t: 0, width: 0.004) }
        let spiralish = Stroke(id: 2, points: pts, isPencil: false, isShape: true)
        let u = ShapeUnravel(stroke: spiralish, x: 0.25, y: 0.5)
        XCTAssertFalse(u.closed)
        XCTAssertEqual(u.origin, 0.25, accuracy: 0.011)
        XCTAssertEqual(u.reach, 0.75, accuracy: 0.011)
        // Points the same distance either side fade together.
        XCTAssertEqual(u.alpha(along: 0.1, progress: 0.3), u.alpha(along: 0.4, progress: 0.3), accuracy: 1e-3)
        XCTAssertTrue(u.isFinished(age: u.duration))
    }

    func testRemoveShapesTakesOnlyTouchedShapesWhole() {
        var doc = InkDocument()
        var ring = Stroke.circle(id: 1, centerX: 0.5, centerY: 0.5, radius: 0.1, width: 0.005)
        ring.isShape = true
        var filled = Stroke.circle(id: 2, centerX: 0.2, centerY: 0.2, radius: 0.05, width: 0.005)
        filled.isShape = true; filled.filled = true
        let line = Stroke(id: 3, points: [InkPoint(x: 0.55, y: 0.4, t: 0, width: 0.005),
                                         InkPoint(x: 0.65, y: 0.4, t: 0, width: 0.005)], isPencil: false)
        doc.append(ring); doc.append(filled); doc.append(line)
        // Inside the plain ring (not filled) touches nothing.
        XCTAssertTrue(doc.removeShapes(touchedAtX: 0.5, y: 0.5, radius: 0.01).isEmpty)
        // Inside the filled shape takes it.
        XCTAssertEqual(doc.removeShapes(touchedAtX: 0.2, y: 0.2, radius: 0.01).map(\.id), [2])
        // On the ring's outline takes the ring whole, and leaves the plain line.
        let hit = doc.removeShapes(touchedAtX: 0.6, y: 0.5, radius: 0.01)
        XCTAssertEqual(hit.map(\.id), [1])
        XCTAssertEqual(hit[0].points.count, ring.points.count)
        XCTAssertEqual(doc.strokes.map(\.id), [3])
    }
}
