import XCTest
@testable import InkModel

final class InkQueryTests: XCTestCase {
    private func doc(_ strokes: [Stroke]) -> (InkDocument, InkIndex) {
        var d = InkDocument()
        for s in strokes { d.append(s) }
        return (d, InkIndex(d))
    }

    private func line(id: UInt32, _ a: (Float, Float), _ b: (Float, Float), n: Int = 20) -> Stroke {
        Stroke(id: id, points: (0...n).map { k in
            let f = Float(k) / Float(n)
            return InkPoint(x: a.0 + (b.0 - a.0) * f, y: a.1 + (b.1 - a.1) * f, t: 0, width: 0.01)
        }, isPencil: false)
    }

    func testHitFindsNearestStrokeAndPosition() {
        let (d, idx) = doc([line(id: 1, (0, 0), (1, 0)), line(id: 2, (0, 0.2), (1, 0.2))])
        let h = d.hit(x: 0.25, y: 0.03, radius: 0.04, index: idx)
        XCTAssertEqual(h?.strokeID, 1)
        XCTAssertEqual(h!.along, 0.25, accuracy: 1e-4)
        XCTAssertEqual(h!.length, 1, accuracy: 1e-4)
        XCTAssertEqual(h!.y, 0, accuracy: 1e-6)
        XCTAssertNil(d.hit(x: 0.5, y: 0.1, radius: 0.04, index: idx))
    }

    func testCrossingReturnsPointAndOtherDirection() {
        let (d, idx) = doc([line(id: 3, (0, 0), (1, 0))])
        let c = d.crossing(x0: 0.4, y0: -0.1, x1: 0.4, y1: 0.1, index: idx)
        XCTAssertEqual(c?.strokeID, 3)
        XCTAssertEqual(c!.x, 0.4, accuracy: 1e-5)
        XCTAssertEqual(c!.dirX, 1, accuracy: 1e-5)
        XCTAssertNil(d.crossing(x0: 0.4, y0: 0.05, x1: 0.4, y1: 0.1, index: idx))
    }

    func testIndexSkipsFarStrokes() {
        let (_, idx) = doc([line(id: 1, (0, 0), (0.1, 0))])
        XCTAssertFalse(idx.near(0, x0: 0.5, y0: 0.5, x1: 0.6, y1: 0.6, pad: 0.01))
        XCTAssertTrue(idx.near(0, x0: 0.05, y0: 0.0, x1: 0.05, y1: 0.0, pad: 0.01))
    }

    func testFillTriangulatesAConcavePolygon() {
        // An L shape: 6 corners, 4 triangles, total area 3 (of the unit squares).
        let pts: [(Float, Float)] = [(0, 0), (2, 0), (2, 1), (1, 1), (1, 2), (0, 2)]
        let outline = pts.map { InkPoint(x: $0.0, y: $0.1, t: 0, width: 0.01) }
        var out: [InkVertex] = []
        FillTessellator.append(outline, alpha: 0.2, into: &out)
        XCTAssertEqual(out.count, 12)
        var area: Float = 0
        for k in stride(from: 0, to: out.count, by: 3) {
            let a = out[k], b = out[k + 1], c = out[k + 2]
            area += abs((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)) / 2
        }
        XCTAssertEqual(area, 3, accuracy: 1e-4, "ear clipping covers exactly the inside")
    }

    func testErasingAFilledOutlineDropsTheFill() {
        var d = InkDocument()
        var s = line(id: 1, (0, 0), (1, 0))
        s.filled = true
        d.append(s)
        var erased: [SIMD2<Float>] = []
        d.erase(x: 0.5, y: 0, radius: 0.05, erased: &erased)
        XCTAssertTrue(d.strokes.allSatisfy { !$0.filled })
    }
}
