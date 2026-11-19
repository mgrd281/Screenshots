import XCTest
@testable import Tendedero

/// Studio's captions: the words heard made into short lines, broken where
/// the speaker pauses or a sentence ends, each long enough to read.
final class StudioCaptionsTests: XCTestCase {
    private func words(_ spoken: [(String, Double)]) -> [StudioCaptions.Word] {
        spoken.map { StudioCaptions.Word(text: $0.0, start: $0.1, end: $0.1 + 0.3) }
    }

    func testAPauseStartsANewLine() {
        let lines = StudioCaptions.lines(words([("Open", 0), ("the", 0.35), ("invoice", 0.7), ("then", 3), ("send", 3.35), ("it", 3.7)]))
        XCTAssertEqual(lines.map(\.text), ["Open the invoice", "then send it"])
        XCTAssertEqual(lines[0].start, 0)
        XCTAssertEqual(lines[1].start, 3)
    }

    func testALineHoldsNoMoreThanItCanShow() {
        let long = (0..<20).map { ("word\($0)", Double($0) * 0.3) }
        let lines = StudioCaptions.lines(words(long))
        XCTAssertGreaterThan(lines.count, 1)
        for line in lines { XCTAssertLessThanOrEqual(line.text.count, StudioCaptions.longest) }
        XCTAssertEqual(lines.map(\.text).joined(separator: " ").split(separator: " ").count, 20)
    }

    func testASentencesEndEndsTheLine() {
        let lines = StudioCaptions.lines(words([("This", 0), ("is", 0.3), ("the", 0.6), ("form.", 0.9), ("Type", 1.2), ("here", 1.5)]))
        XCTAssertEqual(lines.map(\.text), ["This is the form.", "Type here"])
    }

    func testEachLineStaysLongEnoughAndGoesBeforeTheNext() {
        let lines = StudioCaptions.lines([StudioCaptions.Word(text: "Hi", start: 1, end: 1.1),
                                          StudioCaptions.Word(text: "there", start: 3, end: 3.2)])
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].end, 1 + StudioCaptions.shortestTime, accuracy: 0.0001)
        let close = StudioCaptions.lines([StudioCaptions.Word(text: "One.", start: 1, end: 1.1),
                                          StudioCaptions.Word(text: "Two", start: 1.9, end: 2.0)], spaced: true)
        XCTAssertLessThanOrEqual(close[0].end, close[1].start)
    }

    func testWordsWrittenWithoutSpacesAreJoinedWithout() {
        let lines = StudioCaptions.lines(words([("请", 0), ("打开", 0.3), ("发票", 0.6)]), spaced: false)
        XCTAssertEqual(lines.map(\.text), ["请打开发票"])
        XCTAssertFalse(StudioCaptions.isSpaced(Locale(identifier: "zh-Hans")))
        XCTAssertTrue(StudioCaptions.isSpaced(Locale(identifier: "ar")))
    }

    func testCaptionsAreKeptWithTheWorkAndMoveWithATrim() throws {
        var project = StudioProject()
        project.captions = [StudioCaption(text: "Open it", start: 1, end: 2), StudioCaption(text: "Gone", start: 0, end: 0.5)]
        let read = try JSONDecoder().decode(StudioProject.self, from: JSONEncoder().encode(project))
        XCTAssertEqual(read.captions, project.captions)
        let trimmed = project.trimmed(from: 0.6, keeping: 5)
        XCTAssertEqual(trimmed.captions.map(\.text), ["Open it"])
        XCTAssertEqual(trimmed.captions[0].start, 0.4, accuracy: 0.0001)
    }
}
