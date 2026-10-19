import XCTest
@testable import Tendedero

final class RecordingSoundTests: XCTestCase {
    func testWhatEachChoiceRecords() {
        XCTAssertEqual(RecordingSound.allCases.map(\.hasMac), [false, true, false, true])
        XCTAssertEqual(RecordingSound.allCases.map(\.hasVoice), [false, false, true, true])
    }

    func testNoSoundUntilChosen() {
        let key = "recordingSound"
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(RecordingSound.current, .none)
        RecordingSound.current = .both
        XCTAssertEqual(RecordingSound.current, .both)
    }
}
