import XCTest
import GestureEngine
@testable import ResponseMapping

final class HapticMappingTests: XCTestCase {
    let set = ResponseSet.base

    private func haptics(_ m: ResponseMapper, _ e: GestureEvent) -> [HapticCommand] {
        var h: [HapticCommand] = []
        m.map(e, visual: { _ in }, haptic: { h.append($0) })
        return h
    }

    private func ev(_ id: GestureID, _ phase: GesturePhase, speed: Float = 0, magnitude: Float = 0,
                    tempo: Float = 0, touch: UInt16 = 1) -> GestureEvent {
        GestureEvent(gesture: id, phase: phase, timestamp: 0, x: 0, y: 0, speed: speed,
                     magnitude: magnitude, tempo: tempo, touchID: touch)
    }

    func testPaletteCoversAppendixB() {
        for name in HapticName.allCases where name != .none {
            let r = set.recipe(name)
            XCTAssertNotNil(r, name.rawValue)
            for e in r?.events ?? [] {
                XCTAssert((0...1).contains(e.intensity) && (0...1).contains(e.sharpness), name.rawValue)
            }
        }
        XCTAssertEqual(set.recipe(.tick)?.events.first?.intensity, 0.4)
        XCTAssertEqual(set.recipe(.thud)?.events.first?.sharpness, 0.2)
        XCTAssertEqual(set.recipe(.pulse)?.events.count, 2)
        XCTAssertEqual(set.recipe(.pulse)!.events[1].time, 0.12, accuracy: 1e-9)
        XCTAssertTrue((5...8).contains(set.recipe(.burst)!.events.count))
        XCTAssertEqual(set.recipe(.texture)?.held, true)
    }

    func testDrawTextureStartsFollowsSpeedAndStopsOnLift() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        let start = haptics(m, ev(.g7, .began, speed: 100))
        XCTAssertEqual(start.map(\.phase), [.start])
        XCTAssertEqual(start[0].name, .texture)
        let slow = haptics(m, ev(.g7, .changed, speed: 200))[0]
        let fast = haptics(m, ev(.g7, .changed, speed: 1800))[0]
        XCTAssertEqual(slow.phase, .update)
        XCTAssertEqual(slow.key, start[0].key)
        XCTAssertGreaterThan(fast.intensity, slow.intensity, "texture follows finger speed")
        XCTAssertGreaterThan(fast.sharpness!, slow.sharpness!)
        let stop = haptics(m, ev(.g7, .ended))
        XCTAssertEqual(stop.map(\.phase), [.stop], "held haptics stop the moment the touch ends")
        XCTAssertEqual(stop[0].key, start[0].key)
        XCTAssertTrue(haptics(m, ev(.g7, .changed, speed: 500)).isEmpty, "nothing left running")
    }

    func testCancelledHoldStopsItsSwell() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        let start = haptics(m, ev(.g5, .began, magnitude: 0.4))
        XCTAssertEqual(start.first?.name, .swell)
        XCTAssertEqual(haptics(m, ev(.g5, .cancelled)).map(\.phase), [.stop])
    }

    func testDoubleTapAddsADelayedThud() {
        let h = haptics(ResponseMapper(set: set, hapticsAvailable: true), ev(.g2, .began))
        XCTAssertEqual(h.map(\.name), [.thud], "G1 supplies the tick")
        XCTAssertEqual(h[0].delay, 0.08, accuracy: 1e-9)
    }

    func testRhythmPulseLoopsAtTheTappedTempo() {
        let h = haptics(ResponseMapper(set: set, hapticsAvailable: true), ev(.g4, .began, tempo: 2))
        XCTAssertEqual(h.first?.name, .pulse)
        XCTAssertEqual(h.first!.loopPeriod!, 0.5, accuracy: 1e-6)
        XCTAssertEqual(h.first?.loopFor, 8)
    }

    func testSlingshotSwellsThenSnapsOnRelease() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        XCTAssertEqual(haptics(m, ev(.g13, .began, magnitude: 30)).map(\.phase), [.start])
        let end = haptics(m, ev(.g13, .ended, magnitude: 200))
        XCTAssertEqual(end.map(\.phase), [.stop, .play])
        XCTAssertEqual(end.map(\.name), [.swell, .snap])
    }

    func testOrbitPulsesOncePerRevolution() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        XCTAssertTrue(haptics(m, ev(.g21, .began, magnitude: 0.05)).isEmpty)
        var plays = 0
        for mag: Float in [0.3, 0.7, 1.05, 1.4, 1.9, 2.02, 2.5] {
            plays += haptics(m, ev(.g21, .changed, magnitude: mag)).filter { $0.phase == .play }.count
        }
        XCTAssertEqual(plays, 2)
    }

    func testSpiralDirectionPicksTheHaptic() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        XCTAssertEqual(haptics(m, ev(.g11, .fired, magnitude: 2)).map(\.name), [.swell])
        XCTAssertEqual(haptics(m, ev(.g11, .fired, magnitude: -2)).map(\.name), [.settle])
    }

    func testThreeFingerTapAndSwipeFeelDifferent() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        XCTAssertEqual(haptics(m, ev(.g22, .began)).map(\.name), [.burst])
        let swipe = haptics(m, ev(.g22, .fired))
        XCTAssertEqual(swipe.map(\.name), [.texture])
        XCTAssertEqual(swipe[0].phase, .play, "a one-shot of the held recipe")
        XCTAssertEqual(swipe[0].duration, 0.35)
    }

    func testCometBounceTicks() {
        var h: [HapticCommand] = []
        ResponseMapper(set: set, hapticsAvailable: true).haptics(for: .g8, moment: .bounce) { h.append($0) }
        XCTAssertEqual(h.map(\.name), [.tick])
        XCTAssertEqual(h[0].intensity, 0.5)
    }

    func testIdleHasNoHapticAndIPadGetsNone() {
        XCTAssertTrue(haptics(ResponseMapper(set: set, hapticsAvailable: true), ev(.g32, .began)).isEmpty)
        let ipad = ResponseMapper(set: set, hapticsAvailable: false)
        for id in GestureID.allCases {
            XCTAssertTrue(haptics(ipad, ev(id, .began)).isEmpty, id.rawValue)
            XCTAssertTrue(haptics(ipad, ev(id, .fired)).isEmpty, id.rawValue)
        }
    }

    func testEveryGestureButIdleHasACue() {
        for id in GestureID.allCases where id != .g32 {
            XCTAssertFalse(set.response(for: id)!.hapticCues.isEmpty, id.rawValue)
        }
    }
}
