import XCTest
import GestureEngine
@testable import ResponseMapping

final class ResponseMappingTests: XCTestCase {
    let set = ResponseSet.base

    // MARK: Loader

    func testBaseSetLoadsAllThirtyTwoGestures() {
        XCTAssertEqual(set.responses.count, 32)
        for id in GestureID.allCases { XCTAssertNotNil(set.response(for: id), id.rawValue) }
        XCTAssertEqual(set.visualBoostWhenNoHaptics, 1.2)
        XCTAssertEqual(set.response(for: .g7)?.persistence, .ink)
        XCTAssertEqual(set.response(for: .g2)?.haptics, [.tick, .thud])
        XCTAssertEqual(set.response(for: .g32)?.haptics, [.none])
    }

    func testBaseSetRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(set)
        XCTAssertEqual(try ResponseSet.load(from: data), set)
    }

    func testEveryM2GestureHasEffects() {
        for id in [GestureID.g1, .g2, .g3, .g4, .g5, .g6, .g31] {
            XCTAssertFalse(set.response(for: id)!.effects.isEmpty, id.rawValue)
        }
    }

    // MARK: Lifetime

    func testPersistenceDurationsMatchAppendixB() {
        XCTAssertLessThan(Persistence.instant.fadeDuration!, 0.3)
        XCTAssertEqual(Persistence.short.fadeDuration, 1)
        XCTAssertEqual(Persistence.medium.fadeDuration, 4)
        XCTAssertEqual(Persistence.long.fadeDuration, 12)
        XCTAssertNil(Persistence.ink.fadeDuration)
        XCTAssertNil(Persistence.ambient.fadeDuration)
    }

    func testLifetimeFadesAndEnds() {
        XCTAssertEqual(Lifetime.opacity(age: 0, life: 1), 1)
        XCTAssertGreaterThan(Lifetime.opacity(age: 0.5, life: 1), 0)
        XCTAssertLessThan(Lifetime.opacity(age: 0.5, life: 1), 1)
        XCTAssertEqual(Lifetime.opacity(age: 1, life: 1), 0)
        XCTAssertFalse(Lifetime.isAlive(age: 1.01, life: 1))
    }

    func testAmbientLastsWhileHeldThenFadesOverOneSecond() {
        XCTAssertEqual(Lifetime.opacity(age: 30, life: nil), 1)
        XCTAssertTrue(Lifetime.isAlive(age: 30, life: nil))
        XCTAssertEqual(Lifetime.opacity(age: 30.5, life: nil, releasedAt: 30), 0.5, accuracy: 1e-6)
        XCTAssertFalse(Lifetime.isAlive(age: 31.01, life: nil, releasedAt: 30))
    }

    // MARK: Mapper

    private func collect(_ m: ResponseMapper, _ e: GestureEvent) -> ([EffectCommand], [HapticCommand]) {
        var v: [EffectCommand] = [], h: [HapticCommand] = []
        m.map(e, visual: { v.append($0) }, haptic: { h.append($0) })
        return (v, h)
    }

    private func spawns(_ cmds: [EffectCommand]) -> [EffectSpawn] {
        cmds.compactMap { if case .spawn(let s) = $0 { return s } else { return nil } }
    }

    func testTapSpawnsRingAndDotOnBeganOnly() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        let began = spawns(collect(m, GestureEvent(gesture: .g1, phase: .began, timestamp: 0, x: 10, y: 20, magnitude: 10)).0)
        XCTAssertEqual(began.map(\.kind), [.ring, .dot])
        XCTAssertEqual(began[0].x, 10)
        XCTAssertEqual(began[0].duration, 0.6)
        XCTAssertTrue(collect(m, GestureEvent(gesture: .g1, phase: .ended, timestamp: 0.1, x: 10, y: 20)).0.isEmpty)
    }

    func testContactSizeScalesTapRing() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        let small = spawns(collect(m, GestureEvent(gesture: .g1, phase: .began, timestamp: 0, x: 0, y: 0, magnitude: 6)).0)[0]
        let large = spawns(collect(m, GestureEvent(gesture: .g1, phase: .began, timestamp: 0, x: 0, y: 0, magnitude: 30)).0)[0]
        XCTAssertGreaterThan(large.radius, small.radius)
    }

    func testLongPressSpawnsUpdatesAndReleasesTheSameKeys() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        let began = spawns(collect(m, GestureEvent(gesture: .g5, phase: .began, timestamp: 0.4, x: 0, y: 0, magnitude: 0.4, touchID: 3)).0)
        XCTAssertTrue(began.allSatisfy { $0.key != 0 && $0.duration == nil })
        let keys = Set(began.map(\.key))

        let changed = collect(m, GestureEvent(gesture: .g5, phase: .changed, timestamp: 1, x: 0, y: 0, magnitude: 1, touchID: 3)).0
        var updatedKeys = Set<UInt64>()
        for c in changed { if case .update(let k, _, _, _, _) = c { updatedKeys.insert(k) } }
        XCTAssertEqual(updatedKeys, keys)

        let ended = collect(m, GestureEvent(gesture: .g5, phase: .ended, timestamp: 1, x: 0, y: 0, touchID: 3)).0
        var released = Set<UInt64>()
        for c in ended { if case .release(let k) = c { released.insert(k) } }
        XCTAssertEqual(released, keys)
    }

    func testRhythmPulseIsOnePerCanvasAndReplaces() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        let a = spawns(collect(m, GestureEvent(gesture: .g4, phase: .began, timestamp: 0, x: 0, y: 0, tempo: 2, touchID: 1)).0)[0]
        let b = spawns(collect(m, GestureEvent(gesture: .g4, phase: .began, timestamp: 1, x: 50, y: 0, tempo: 2, touchID: 5)).0)[0]
        XCTAssertNotEqual(a.key, 0)
        XCTAssertEqual(a.key, b.key, "tapping elsewhere moves the same pulse")
        XCTAssertEqual(a.tempo, 2)
        XCTAssertEqual(a.duration, 8)

        let confirmed = collect(m, GestureEvent(gesture: .g4, phase: .ended, timestamp: 1.1, x: 50, y: 0, touchID: 5)).0
        XCTAssertTrue(confirmed.isEmpty, "a confirmed rhythm tap keeps pulsing")
        let cancelled = collect(m, GestureEvent(gesture: .g4, phase: .cancelled, timestamp: 1.6, x: 80, y: 0, touchID: 6)).0
        XCTAssertEqual(cancelled, [.release(key: a.key)], "a cancelled rhythm tap fades the pulse")
    }

    func testFastLiftLeavesTrailSlowLiftDoesNot() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        let slow = spawns(collect(m, GestureEvent(gesture: .g31, phase: .fired, timestamp: 0, x: 0, y: 0, speed: 100)).0)
        let fast = spawns(collect(m, GestureEvent(gesture: .g31, phase: .fired, timestamp: 0, x: 0, y: 0, speed: 1500, directionX: 1)).0)
        XCTAssertEqual(slow.count, 1)
        XCTAssertEqual(fast.count, 6)
        XCTAssertLessThan(fast.last!.x, 0, "trail sits behind the direction of travel")
        XCTAssertGreaterThan(fast[0].radius, slow[0].radius)
    }

    func testNoHapticsBoostsVisualsAndEmitsNoHaptics() {
        let e = GestureEvent(gesture: .g1, phase: .began, timestamp: 0, x: 0, y: 0, magnitude: 10)
        let (withV, withH) = collect(ResponseMapper(set: set, hapticsAvailable: true), e)
        let (noV, noH) = collect(ResponseMapper(set: set, hapticsAvailable: false), e)
        XCTAssertEqual(withH.map(\.name), [.tick])
        XCTAssertTrue(noH.isEmpty)
        XCTAssertEqual(spawns(noV)[0].intensity, spawns(withV)[0].intensity * 1.2, accuracy: 1e-5)
    }

    func testEveryM3GestureHasEffects() {
        for id in [GestureID.g8, .g9, .g10, .g11, .g12, .g13, .g14, .g15] {
            XCTAssertFalse(set.response(for: id)!.effects.isEmpty, id.rawValue)
        }
    }

    func testSpiralDirectionPicksItsEffects() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        let inward = spawns(collect(m, GestureEvent(gesture: .g11, phase: .fired, timestamp: 0, x: 0, y: 0, magnitude: 2, size: 100)).0)
        let outward = spawns(collect(m, GestureEvent(gesture: .g11, phase: .fired, timestamp: 0, x: 0, y: 0, magnitude: -2, size: 100)).0)
        XCTAssertEqual(inward.map(\.kind), [.vortex, .flash, .twist, .pull], "inward ends in a flash and drags ink in")
        XCTAssertEqual(outward.map(\.kind), [.vortex, .ring])
        XCTAssertGreaterThan(inward[0].magnitude, 0)
    }

    func testSlingshotTetherFollowsThenLaunchesOnRelease() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        let began = spawns(collect(m, GestureEvent(gesture: .g13, phase: .began, timestamp: 0, x: 50, y: 0,
                                                   magnitude: 50, touchID: 2, originX: 0, originY: 0)).0)
        XCTAssertEqual(began.map(\.kind), [.tether], "the launch waits for the release")
        XCTAssertEqual(began[0].originX, 0)
        let end = collect(m, GestureEvent(gesture: .g13, phase: .ended, timestamp: 1, x: 200, y: 0,
                                          magnitude: 200, touchID: 2, originX: 0, originY: 0)).0
        XCTAssertTrue(end.contains(.release(key: began[0].key)), "the tether snaps back")
        let launch = spawns(end)
        XCTAssertEqual(launch.map(\.kind), [.launch])
        XCTAssertGreaterThan(launch[0].radius, set.response(for: .g13)!.effects[1].radius, "a long stretch launches harder")
    }

    func testEveryM4GestureHasEffects() {
        for id in [GestureID.g16, .g17, .g18, .g19, .g20, .g21, .g22, .g23, .g24, .g25, .g26] {
            XCTAssertFalse(set.response(for: id)!.effects.isEmpty, id.rawValue)
        }
    }

    func testThreeFingerTapAndSwipeGetDifferentEffects() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        let pts: [Float] = [0, 0, 50, 0, 25, 40]
        let tap = spawns(collect(m, GestureEvent(gesture: .g22, phase: .began, timestamp: 0, x: 25, y: 13, touchPoints: pts)).0)
        let swipe = spawns(collect(m, GestureEvent(gesture: .g22, phase: .fired, timestamp: 0, x: 25, y: 13, directionX: 1)).0)
        XCTAssertEqual(tap.map(\.kind), [.ring, .filament])
        XCTAssertTrue(tap[0].atEachPoint, "one ripple per finger")
        XCTAssertEqual(tap[1].points, pts)
        XCTAssertEqual(swipe.map(\.kind), [.sweep, .wave])
    }

    func testOrbitCoreSitsAtTheHeldFinger() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        let s = spawns(collect(m, GestureEvent(gesture: .g21, phase: .began, timestamp: 0, x: 300, y: 300,
                                               originX: 200, originY: 310)).0)
        XCTAssertEqual(s[0].kind, .orb)
        XCTAssertEqual(s[0].x, 200); XCTAssertEqual(s[0].y, 310)
        XCTAssertEqual(s[1].x, 300, "the trail follows the orbiting finger")
    }

    func testSpreadReplacesTheGatheredOrb() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        let gather = spawns(collect(m, GestureEvent(gesture: .g24, phase: .ended, timestamp: 0, x: 0, y: 0, magnitude: 0.9)).0)
        let orb = gather.first { $0.kind == .orb }!
        XCTAssertNil(orb.duration, "the orb stays until the spread")
        let spread = spawns(collect(m, GestureEvent(gesture: .g24, phase: .ended, timestamp: 1, x: 0, y: 0, magnitude: -0.9, touchID: 3)).0)
        XCTAssertTrue(spread.contains { $0.key == orb.key && $0.kind == .flash }, "same key: the nova replaces the orb")
        XCTAssertEqual(m.keyFor(.g24, slot: 9), orb.key)
    }

    func testEveryGestureNowHasEffects() {
        // G7 is drawn by the ink layer itself; every other gesture has a recipe.
        for id in GestureID.allCases where id != .g7 {
            XCTAssertFalse(set.response(for: id)!.effects.isEmpty, id.rawValue)
        }
    }

    func testLongerStrokeRingsLonger() {
        let m = ResponseMapper(set: set, hapticsAvailable: true)
        func ring(_ length: Float) -> Double {
            spawns(collect(m, GestureEvent(gesture: .g27, phase: .began, timestamp: 0, x: 0, y: 0,
                                           magnitude: length, size: 10, targetID: 4)).0)[0].duration!
        }
        XCTAssertGreaterThan(ring(700), ring(80), "stroke length sets ring time")
        let pluck = spawns(collect(m, GestureEvent(gesture: .g27, phase: .began, timestamp: 0, x: 0, y: 0,
                                                   magnitude: 300, size: 120)).0)[0]
        XCTAssertEqual(pluck.kind, .pluck)
        XCTAssertEqual(pluck.size, 120, "carries the distance along the stroke")
    }

    func testSwappingTheSetChangesTheReaction() {
        var custom = set
        custom.responses["G1"]!.effects[0].radius = 40
        let e = GestureEvent(gesture: .g1, phase: .began, timestamp: 0, x: 0, y: 0, magnitude: 6)
        let base = spawns(collect(ResponseMapper(set: set, hapticsAvailable: true), e).0)[0]
        let swapped = spawns(collect(ResponseMapper(set: custom, hapticsAvailable: true), e).0)[0]
        XCTAssertLessThan(swapped.radius, base.radius, "R9: reactions come from data, not code")
    }
}
