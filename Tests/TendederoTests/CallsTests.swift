import CoreAudio
import Foundation
import XCTest
@testable import Tendedero

/// Not during a call: on from the start, and without an input device there
/// is no call.
final class CallsTests: XCTestCase {
    func testTheLineKeepsAwayDuringCallsFromTheStart() {
        let key = "callsIgnored"
        let before = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(before, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        MainActor.assumeIsolated {
            XCTAssertTrue(Calls.keepsAway)
            Calls.keepsAway = false
            XCTAssertFalse(Calls.keepsAway)
            XCTAssertFalse(Calls.shared.keepingAway, "off, whatever the microphone does")
        }
    }

    func testWithoutAnInputDeviceThereIsNoCall() {
        XCTAssertFalse(Calls.isRunning(AudioObjectID(kAudioObjectUnknown)))
        // The Mac the tests run on may have no microphone; asking must not fail.
        _ = Calls.isRunning(Calls.defaultInput())
    }
}
