import XCTest
@testable import InkModel

final class InkHistoryTests: XCTestCase {
    private func line(id: UInt32 = 1, from x0: Float = -0.4, to x1: Float = 0.4, y: Float = 0, n: Int = 81) -> Stroke {
        let pts = (0..<n).map { k in InkPoint(x: x0 + (x1 - x0) * Float(k) / Float(n - 1), y: y, t: 0, width: 0.01) }
        return Stroke(id: id, points: pts, isPencil: false)
    }

    func testEraseSplitsAStrokeAroundTheEraser() {
        var doc = InkDocument()
        doc.append(line())
        var erased: [SIMD2<Float>] = []
        XCTAssertTrue(doc.erase(x: 0, y: 0, radius: 0.05, erased: &erased))
        XCTAssertEqual(doc.strokes.count, 2, "one line becomes two pieces")
        XCTAssertFalse(erased.isEmpty)
        XCTAssertTrue(doc.strokes.allSatisfy { $0.points.allSatisfy { abs($0.x) > 0.05 } })
    }

    func testEraseMissLeavesInkAlone() {
        var doc = InkDocument()
        doc.append(line())
        var erased: [SIMD2<Float>] = []
        XCTAssertFalse(doc.erase(x: 0, y: 0.3, radius: 0.05, erased: &erased))
        XCTAssertEqual(doc.strokes.count, 1)
    }

    func testEraseRemovesBlotsUnderTheEraser() {
        var doc = InkDocument()
        doc.append(Stroke(id: 1, points: [], isPencil: false, blots: [InkBlot(x: 0, y: 0, radius: 0.02)]))
        var erased: [SIMD2<Float>] = []
        XCTAssertTrue(doc.erase(x: 0.01, y: 0, radius: 0.03, erased: &erased))
        XCTAssertTrue(doc.strokes.isEmpty)
    }

    func testScribbleEraseIsOneUndo() {
        var h = InkHistory()
        h.record { $0.append(line()) }
        // A scribble erases over several frames after one checkpoint.
        h.checkpoint()
        var erased: [SIMD2<Float>] = []
        for x in stride(from: Float(-0.1), through: 0.1, by: 0.05) {
            h.continueChange { $0.erase(x: x, y: 0, radius: 0.04, erased: &erased) }
        }
        XCTAssertNotEqual(h.document.strokes, [line()])
        XCTAssertTrue(h.undo())
        XCTAssertEqual(h.document.strokes, [line()], "R3: one undo restores everything the scribble erased")
        XCTAssertTrue(h.undo())
        XCTAssertTrue(h.document.isEmpty)
        XCTAssertFalse(h.undo())
    }

    func testConsumedStrokeComesBackWithOneUndo() {
        var h = InkHistory()
        var withStroke = h.document
        withStroke.append(line())
        h.pushUndoState(withStroke)          // G8/G12 consumed it; it never became ink
        XCTAssertTrue(h.document.isEmpty)
        XCTAssertTrue(h.undo())
        XCTAssertEqual(h.document.strokes.count, 1)
    }

    func testNoOpChangeAddsNoUndoStep() {
        var h = InkHistory()
        h.record { _ in }
        XCTAssertFalse(h.canUndo)
    }

    func testUndoDepthIsCapped() {
        var h = InkHistory(limit: 3)
        for k in 0..<10 { h.record { $0.append(line(id: UInt32(k))) } }
        var n = 0
        while h.undo() { n += 1 }
        XCTAssertEqual(n, 3)
    }

    func testCleanCircleIsClosedAndRound() {
        let c = Stroke.circle(id: 1, centerX: 0.1, centerY: -0.1, radius: 0.2, width: 0.01)
        let first = c.points.first!, last = c.points.last!
        XCTAssertEqual(first.x, last.x, accuracy: 1e-5)
        XCTAssertEqual(first.y, last.y, accuracy: 1e-5)
        for p in c.points { XCTAssertEqual(hypot(p.x - 0.1, p.y + 0.1), 0.2, accuracy: 1e-5) }
    }

    func testBlotTessellatesAsAFan() {
        var out: [InkVertex] = []
        BlotTessellator.append(InkBlot(x: 0, y: 0, radius: 0.05), coreFrac: 0.6, segments: 10, into: &out)
        XCTAssertEqual(out.count, 30)
        XCTAssertEqual(out[0].u, 0)
        XCTAssertEqual(out[1].u, 1)
    }
}
