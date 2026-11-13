import XCTest
@testable import InkModel

final class InkModelTests: XCTestCase {
    let space = InkSpace(width: 400, height: 800)

    func testSpaceRoundTrip() {
        let u = space.toUnits(x: 123, y: 456)
        let p = space.toPoints(u)
        XCTAssertEqual(p.x, 123, accuracy: 1e-3)
        XCTAssertEqual(p.y, 456, accuracy: 1e-3)
    }

    func testInkStaysCenteredAcrossRotation() {
        // A point at the center of a portrait canvas is still at the center after rotation.
        let portrait = InkSpace(width: 400, height: 800)
        let landscape = InkSpace(width: 800, height: 400)
        let u = portrait.toUnits(x: 200, y: 400)
        let p = landscape.toPoints(u)
        XCTAssertEqual(p.x, 400, accuracy: 1e-3)
        XCTAssertEqual(p.y, 200, accuracy: 1e-3)
        // Same physical scale: 100 pt right of center stays 100 pt right of center.
        let u2 = portrait.toUnits(x: 300, y: 400)
        XCTAssertEqual(landscape.toPoints(u2).x - 400, 100, accuracy: 1e-3)
    }

    func testPredictedPointsAreReplacedByRealOnes() {
        let b = StrokeBuilder()
        b.begin(id: 1, sample: .init(x: 0, y: 0, t: 0), space: space, brush: .default)
        b.addReal(.init(x: 10, y: 0, t: 0.01))
        b.addPredicted(.init(x: 20, y: 0, t: 0.02))
        b.addPredicted(.init(x: 30, y: 0, t: 0.03))
        XCTAssertEqual(b.points.count, 4)
        XCTAssertEqual(b.predictedCount, 2)
        b.addReal(.init(x: 15, y: 0, t: 0.015))
        XCTAssertEqual(b.predictedCount, 0)
        XCTAssertEqual(b.points.count, 3)
        let stroke = b.finish(final: nil)
        XCTAssertEqual(stroke.points.count, 3)
    }

    func testFinishNeverKeepsPredictedPoints() {
        let b = StrokeBuilder()
        b.begin(id: 1, sample: .init(x: 0, y: 0, t: 0), space: space, brush: .default)
        b.addReal(.init(x: 10, y: 0, t: 0.01))
        b.addPredicted(.init(x: 50, y: 0, t: 0.02))
        XCTAssertEqual(b.finish(final: nil).points.count, 2)
    }

    func testLineThinsAsSpeedRises() {
        func lastWidth(speed: Float) -> Float {
            let b = StrokeBuilder()
            b.begin(id: 1, sample: .init(x: 0, y: 0, t: 0), space: space, brush: .default)
            var x: Float = 0
            for i in 1...30 { x += speed / 120; b.addReal(.init(x: x, y: 0, t: Double(i) / 120)) }
            return b.points.last!.width
        }
        XCTAssertGreaterThan(lastWidth(speed: 200), lastWidth(speed: 3000))
    }

    func testPencilForceWidensLine() {
        func width(force: Float) -> Float {
            let b = StrokeBuilder()
            b.begin(id: 1, sample: .init(x: 0, y: 0, t: 0, force: force, isPencil: true), space: space, brush: .default)
            return b.points[0].width
        }
        XCTAssertGreaterThan(width(force: 1), width(force: 0.1))
    }

    func testDisplacementTracksTapVersusDraw() {
        let b = StrokeBuilder()
        b.begin(id: 1, sample: .init(x: 100, y: 100, t: 0), space: space, brush: .default)
        b.addReal(.init(x: 106, y: 100, t: 0.05))
        XCTAssertLessThan(b.maxDisplacement, 10)
        b.addReal(.init(x: 112, y: 100, t: 0.1))
        XCTAssertGreaterThan(b.maxDisplacement, 10)
    }

    func testTessellationEmitsSixVerticesPerSegmentAndTapers() {
        var points: [InkPoint] = []
        for i in 0..<20 { points.append(InkPoint(x: Float(i) * 0.01, y: 0, t: 0, width: 0.02)) }
        var out: [InkVertex] = []
        StrokeTessellator.append(points, taperStart: true, taperEnd: true, taperLength: 0.04,
                                 taperMinFactor: 0.1, glowFactor: 3, into: &out)
        XCTAssertEqual(out.count, 19 * 6)
        let firstHalf = abs(out[0].y)            // start, tapered
        let midHalf = abs(out[9 * 6].y)          // middle, full width
        XCTAssertLessThan(firstHalf, midHalf)
        XCTAssertEqual(midHalf, 0.02 * 0.5 * 3, accuracy: 1e-5)
    }

    func testSinglePointProducesNoGeometry() {
        var out: [InkVertex] = []
        StrokeTessellator.append([InkPoint(x: 0, y: 0, t: 0, width: 0.01)], taperStart: true, taperEnd: true,
                                 taperLength: 0.04, taperMinFactor: 0.1, glowFactor: 3, into: &out)
        XCTAssertTrue(out.isEmpty)
    }

    func testInkVertexLayoutMatchesShader() {
        XCTAssertEqual(MemoryLayout<InkVertex>.stride, 28)
    }
}
