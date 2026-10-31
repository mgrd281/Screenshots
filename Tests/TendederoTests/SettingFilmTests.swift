import AppKit
import XCTest
@testable import Tendedero

/// Every setting's film: there, short, on the stage, and in order, so none
/// shows empty, runs on or puts a part out of sight.
final class SettingFilmTests: XCTestCase {
    func testEveryFilmIsShortAndOnTheStage() {
        for id in SettingFilm.ID.allCases {
            let film = SettingFilms.film(id)
            XCTAssertFalse(film.symbol.isEmpty, "\(id)")
            XCTAssertGreaterThanOrEqual(film.parts.count, 3, "\(id): too little to see")
            XCTAssertTrue((2...3.5).contains(film.duration), "\(id): \(film.duration) s")
            for part in film.parts {
                XCTAssertFalse(part.keys.isEmpty, "\(id)")
                XCTAssertEqual(part.keys.map(\.t), part.keys.map(\.t).sorted(), "\(id): moments out of order")
                for key in part.keys {
                    XCTAssertTrue((0...1).contains(key.opacity), "\(id)")
                    XCTAssertTrue((-0.25...1.25).contains(key.box.x) && (-0.25...1.25).contains(key.box.y),
                                  "\(id): \(part.kind) off the stage")
                    XCTAssertTrue(key.box.w > 0 && key.box.h > 0 && key.box.w <= 1.5 && key.box.h <= 1.5, "\(id)")
                }
                // A key shows a glyph, never a word: films are not translated.
                if case .key(let glyph) = part.kind { XCTAssertLessThanOrEqual(glyph.count, 3, "\(id): \(glyph)") }
            }
        }
    }

    func testNoTwoSettingsShareAFilm() {
        let ids = SettingFilm.ID.allCases
        for (n, id) in ids.enumerated() {
            for other in ids[(n + 1)...] {
                XCTAssertNotEqual(SettingFilms.film(id).parts, SettingFilms.film(other).parts, "\(id) and \(other)")
            }
        }
    }

    func testEverySymbolIsOneTheMacHas() {
        for id in SettingFilm.ID.allCases {
            let film = SettingFilms.film(id)
            var names = [film.symbol]
            for part in film.parts {
                if case .symbol(let name) = part.kind { names.append(name) }
            }
            for name in names {
                XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), "\(id): \(name)")
            }
        }
    }

    func testNoTwoSettingsShareATile() {
        let symbols = SettingFilm.ID.allCases.map { SettingFilms.film($0).symbol }
        XCTAssertEqual(Set(symbols).count, symbols.count)
    }

    func testEveryPrivateDetailHasAFilmOfItsOwn() {
        let ids = PrivateDetail.allCases.map(SettingFilm.ID.init)
        XCTAssertEqual(Set(ids).count, PrivateDetail.allCases.count)
    }

    func testAPartEasesBetweenItsMomentsAndRestsAfterTheLast() {
        let part = SettingFilm.Part.move(.card(0), .init(0.5, 0.8, 0.2, 0.2), .init(0.3, 0.2, 0.2, 0.2),
                                         start: 0.5, end: 1.2, appear: 0.2, leave: 2)
        XCTAssertNil(part.state(at: 0.1))
        XCTAssertEqual(part.state(at: 0.2)?.opacity, 0)
        XCTAssertEqual(part.state(at: 0.5)?.box.y, 0.8)
        XCTAssertEqual(part.state(at: 0.85)?.box.y ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(part.state(at: 1.6)?.box.x, 0.3)
        XCTAssertEqual(part.state(at: 3)?.opacity, 0)
        XCTAssertEqual(SettingFilm.ease(0), 0)
        XCTAssertEqual(SettingFilm.ease(1), 1)
        XCTAssertEqual(SettingFilm.ease(0.5), 0.5, accuracy: 0.001)
    }
}
