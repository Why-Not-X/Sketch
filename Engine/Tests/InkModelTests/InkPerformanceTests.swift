import XCTest
@testable import InkModel

/// M8: costs that grow with the drawing. Run in release for real numbers:
///   swift test -c release --filter InkPerformanceTests
final class InkPerformanceTests: XCTestCase {
    /// 300 strokes of 200 points: a busy canvas.
    private func bigDocument() -> InkDocument {
        var d = InkDocument()
        for s in 0..<300 {
            let y = Float(s) / 300 - 0.5
            d.append(Stroke(id: UInt32(s), points: (0..<200).map { k in
                InkPoint(x: Float(k) / 200 - 0.5, y: y + 0.01 * sin(Float(k) * 0.3), t: 0, width: 0.012)
            }, isPencil: false))
        }
        return d
    }

    private func time(_ label: String, _ body: () -> Void) -> Double {
        let start = Date()
        body()
        let ms = Date().timeIntervalSince(start) * 1000
        print(String(format: "[perf] %@: %.2f ms", label, ms))
        return ms
    }

    func testFullRebuildCost() {
        let doc = bigDocument()
        var out: [InkVertex] = []
        out.reserveCapacity(400_000)
        let ms = time("tessellate 300 strokes x 200 points") {
            for s in doc.strokes {
                StrokeTessellator.append(s.points, taperStart: true, taperEnd: true, taperLength: 0.04,
                                         taperMinFactor: 0.04, glowFactor: 3.2, into: &out)
            }
        }
        XCTAssertEqual(out.count, 300 * 199 * 6)
        // Generous bound so debug builds pass; the printed number is the measurement.
        XCTAssertLessThan(ms, 500)
    }

    func testEraseAndHitCostOnABusyCanvas() {
        var doc = bigDocument()
        let index = InkIndex(doc)
        var erased: [SIMD2<Float>] = []
        _ = time("erase one scribble step") { _ = doc.erase(x: 0, y: 0, radius: 0.05, erased: &erased) }
        _ = time("hit test") { _ = doc.hit(x: 0.1, y: 0.1, radius: 0.04, index: index) }
        _ = time("crossing test") { _ = doc.crossing(x0: 0.1, y0: -0.5, x1: 0.1, y1: 0.5, index: index) }
        _ = time("rebuild hit index") { _ = InkIndex(doc) }
        XCTAssertFalse(erased.isEmpty)
    }
}
