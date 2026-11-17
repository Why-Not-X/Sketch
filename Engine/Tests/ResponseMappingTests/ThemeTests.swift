import XCTest
@testable import ResponseMapping

final class ThemeTests: XCTestCase {
    func testLibraryLoadsEveryThemeInOrder() {
        let all = ThemeLibrary.all
        XCTAssertTrue(ThemeLibrary.loadErrors.isEmpty, ThemeLibrary.loadErrors.joined(separator: "\n"))
        XCTAssertEqual(all.map(\.id), ["base", "neon", "neon-echoes", "chalk", "paper", "aurora"])
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "ids are unique")
        for t in all { XCTAssertTrue((1...4).contains(t.palette.count), t.id) }
    }

    func testBaseIsTheV1Look() {
        let b = ThemeLibrary.theme(id: "base")!
        XCTAssertEqual(b, .base)
        XCTAssertEqual(b.ink, RGBA(1.0, 0.95, 0.86))
        XCTAssertEqual(b.glowStrength, 0.38)
        XCTAssertEqual(b.inkMode, .single)
        XCTAssertEqual(b.blend, .add)
        XCTAssertNil(b.echo)
        XCTAssertEqual(ResponseSet.base.theme.ink, b.ink, "the v1 response-set theme still decodes")
    }

    func testMissingFieldsFallBackToBase() throws {
        let t = try JSONDecoder().decode(Theme.self, from: Data(#"{"id":"x","name":"X","palette":[[1,0,0]]}"#.utf8))
        XCTAssertEqual(t.palette, [RGBA(1, 0, 0)])
        XCTAssertEqual(t.glowStrength, Theme.base.glowStrength)
        XCTAssertEqual(t.sprite, .soft)
        XCTAssertEqual(t.background, Theme.base.background)
        XCTAssertEqual(t.backgroundEdge, Theme.base.background, "edge defaults to the background")
    }

    func testRoundTrip() throws {
        for t in ThemeLibrary.all {
            XCTAssertEqual(try JSONDecoder().decode(Theme.self, from: JSONEncoder().encode(t)), t, t.id)
        }
    }

    func testLightThemePaintsOverAndDarkThemesAddLight() {
        XCTAssertEqual(ThemeLibrary.theme(id: "paper")?.blend, .over)
        XCTAssertGreaterThan(ThemeLibrary.theme(id: "paper")!.backgroundLuminance, 0.8)
        for id in ["base", "neon", "neon-echoes", "chalk", "aurora"] {
            XCTAssertEqual(ThemeLibrary.theme(id: id)?.blend, .add, id)
            XCTAssertLessThan(ThemeLibrary.theme(id: id)!.backgroundLuminance, 0.25, id)
        }
    }

    func testEffectPaletteRotates() {
        let neon = ThemeLibrary.theme(id: "neon")!
        XCTAssertNotEqual(neon.color(.glow, variant: 0), neon.color(.glow, variant: 1))
        XCTAssertEqual(Theme.base.color(.glow, variant: 0), Theme.base.color(.glow, variant: 3), "Base never rotates")
    }

    func testOnlyNeonEchoesEchoes() {
        XCTAssertEqual(ThemeLibrary.all.filter { $0.echo != nil }.map(\.id), ["neon-echoes"])
    }
}
