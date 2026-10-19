import CoreGraphics
import Foundation
import XCTest
@testable import Tendedero

/// Photos prepared ahead of time, without Photos or a picture: what is kept
/// of a photo, what is left to read, and when preparing waits.
final class PrivacyIndexTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_400_000)

    /// Lines kept as the index keeps them: each word with its place.
    private func kept(_ strings: [String]) -> [Finder.TextLine] {
        strings.enumerated().map { i, string in
            let box = CGRect(x: 0.1, y: 0.9 - CGFloat(i) * 0.03, width: CGFloat(string.count) * 0.01, height: 0.02)
            var words: [Finder.TextLine.Word] = []
            var start: String.Index?
            for index in string.indices + [string.endIndex] {
                if index == string.endIndex || string[index] == " " {
                    if let begun = start {
                        let range = NSRange(begun..<index, in: string)
                        words.append(Finder.TextLine.Word(range: range, box: CGRect(
                            x: box.minX + CGFloat(range.location) * 0.01, y: box.minY,
                            width: CGFloat(range.length) * 0.01, height: box.height)))
                    }
                    start = nil
                } else if start == nil {
                    start = index
                }
            }
            return Finder.TextLine(string: string, box: box, words: words)
        }
    }

    func testAPhotoIsKeptWithItsLinesAndWhatTheyHold() throws {
        let lines = kept(["Arztbrief", "Patient: Max Mustermann", "max.mustermann@example.com"])
        let photo = IndexedPhoto(id: "A1", stamp: "1179x2556@1", created: now, width: 1179, height: 2556, lines: lines,
                                 read: now)
        XCTAssertEqual(photo.status, .ready)
        XCTAssertTrue(photo.kinds.contains("names"), "\(photo.kinds)")
        XCTAssertTrue(photo.kinds.contains("emails"), "\(photo.kinds)")
        XCTAssertEqual(photo.roles, ["patient"])
        // Written and read back, as the iPhone keeps it.
        let back = try JSONDecoder().decode(IndexedPhoto.self, from: JSONEncoder().encode(photo))
        XCTAssertEqual(back, photo)
        let again = back.textLines
        XCTAssertEqual(again.map(\.string), lines.map(\.string))
        // Where a name is comes from its words' places, without Vision.
        let line = again[1].string
        let name = try XCTUnwrap(line.range(of: "Max Mustermann"))
        let place = try XCTUnwrap(again[1].box(for: name))
        XCTAssertEqual(place.minX, 0.1 + 9 * 0.01, accuracy: 0.0001)
        XCTAssertEqual(place.width, 14 * 0.01, accuracy: 0.0001)
        // Part of a word, by its share of the letters.
        let part = try XCTUnwrap(again[1].box(for: try XCTUnwrap(line.range(of: "Muster"))))
        XCTAssertEqual(part.width, 6 * 0.01, accuracy: 0.0001)
        XCTAssertNil(again[1].box(for: try XCTUnwrap(line.range(of: " "))), "a space alone is in no word")
    }

    func testCoveringStartsFromWhatWasKept() {
        let lines = IndexedPhoto(id: "A1", stamp: "s", created: now, width: 100, height: 200,
                                 lines: kept(["Patient: Max Mustermann", "Überweisender Arzt: Dr. Klaus Weber"]),
                                 read: now).textLines
        let found = Finder.findings(lines.map(\.string), boxes: lines.map(\.box), part: { lines[$0].box(for: $1) },
                                    [.patientNames])
        XCTAssertEqual(found.hits.count, 1, "the patient, and not the doctor, with no second reading")
        XCTAssertEqual(found.hits.first?.line, 0)
    }

    func testWhatIsLeftToReadNewestFirst() {
        func candidate(_ id: String, _ days: Double, stamp: String = "s") -> IndexPlan.Candidate {
            IndexPlan.Candidate(id: id, stamp: stamp, created: now.addingTimeInterval(-days * 86_400))
        }
        var manifest = IndexManifest()
        manifest.entries["read"] = .init(stamp: "s", version: IndexedPhoto.version, status: .ready, created: nil,
                                         bytes: 1000, checked: now)
        manifest.entries["changed"] = .init(stamp: "old", version: IndexedPhoto.version, status: .ready, created: nil,
                                            bytes: 1000, checked: now)
        manifest.entries["older"] = .init(stamp: "s", version: IndexedPhoto.version - 1, status: .ready, created: nil,
                                          bytes: 1000, checked: now)
        manifest.entries["cloud"] = .init(stamp: "s", version: IndexedPhoto.version, status: .inCloud, created: nil,
                                          bytes: 0, checked: now.addingTimeInterval(-3600))
        manifest.entries["gone"] = .init(stamp: "s", version: IndexedPhoto.version, status: .ready, created: nil,
                                         bytes: 500, checked: now)
        let candidates = [candidate("read", 1), candidate("changed", 5), candidate("older", 3), candidate("new", 2),
                          candidate("cloud", 0)]
        XCTAssertEqual(IndexPlan.pending(candidates, in: manifest, now: now).map(\.id), ["new", "older", "changed"])
        // A day later, the photo only in iCloud is tried again, after the rest.
        XCTAssertEqual(IndexPlan.pending(candidates, in: manifest, now: now.addingTimeInterval(86_400)).last?.id,
                       "cloud")
        XCTAssertEqual(IndexPlan.stale(in: manifest, keeping: candidates), ["gone"])
        let progress = IndexPlan.progress(candidates, in: manifest)
        XCTAssertEqual(progress, IndexPlan.Progress(total: 5, ready: 1, inCloud: 1, failed: 0, remaining: 3))
        XCTAssertEqual(progress.fraction, 0.25, accuracy: 0.0001)
        XCTAssertEqual(manifest.bytes, 3500)
    }

    func testPreparingWaitsForTheOwnerAndTheDevice() {
        var settings = IndexSettings(isOn: true)
        XCTAssertNil(IndexPlan.pause(settings: settings, lowPower: false, hot: false, lowMemory: false, busy: false))
        XCTAssertEqual(IndexPlan.pause(settings: settings, lowPower: true, hot: false, lowMemory: false, busy: false),
                       .lowPower)
        XCTAssertEqual(IndexPlan.pause(settings: settings, lowPower: false, hot: true, lowMemory: false, busy: false), .hot)
        XCTAssertEqual(IndexPlan.pause(settings: settings, lowPower: false, hot: false, lowMemory: false, busy: true),
                       .busy)
        settings.paused = true
        XCTAssertEqual(IndexPlan.pause(settings: settings, lowPower: true, hot: true, lowMemory: true, busy: true), .owner)
    }

    func testTheSettingsAreKeptAndOffUntilChosen() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PrivacyIndexTests"))
        defaults.removePersistentDomain(forName: "PrivacyIndexTests")
        XCTAssertEqual(IndexSettings.load(from: defaults), IndexSettings(), "off, screenshots, 60 days")
        XCTAssertFalse(IndexSettings.load(from: defaults).isOn)
        XCTAssertEqual(IndexSettings().days, 60)
        IndexSettings(isOn: true, scope: .selected, paused: true, selected: ["A1"]).save(to: defaults)
        XCTAssertEqual(IndexSettings.load(from: defaults).selected, ["A1"])
        XCTAssertEqual(IndexSettings.load(from: defaults).scope, .selected)
        defaults.removePersistentDomain(forName: "PrivacyIndexTests")
    }

    func testAChangeOrAnotherVersionGivesAnotherStamp() {
        let date = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(IndexedPhoto.stamp(width: 10, height: 20, modified: date), "10x20@1000")
        XCTAssertNotEqual(IndexedPhoto.stamp(width: 10, height: 20, modified: date.addingTimeInterval(5)), "10x20@1000")
        let photo = IndexedPhoto(id: "A", stamp: "s", created: nil, width: 1, height: 1, status: .failed, read: now)
        XCTAssertFalse(photo.isCurrent(stamp: "s"), "a failure is tried again")
    }
}
