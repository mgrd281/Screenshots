import Foundation
import XCTest
@testable import Tendedero

/// How Settings names a folder: from the home folder down, as the Finder
/// shows it, so "Pictures › Snapfly" rather than a path.
final class SettingsTests: XCTestCase {
    func testAFolderIsNamedFromTheHomeFolderDown() throws {
        let home = URL(fileURLWithPath: String(cString: try XCTUnwrap(getpwuid(getuid())).pointee.pw_dir))
        let parent = home.appendingPathComponent("Snapfly Test \(UUID().uuidString)", isDirectory: true)
        let inside = parent.appendingPathComponent("Inside", isDirectory: true)
        XCTAssertEqual(Folders.placeName(inside), "\(parent.lastPathComponent) › Inside")
        XCTAssertEqual(Folders.placeName(home), FileManager.default.displayName(atPath: home.path))
        // Outside the home folder, from the top of the disk.
        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        XCTAssertEqual(Folders.placeName(applications), FileManager.default.displayName(atPath: applications.path))
        XCTAssertEqual(Folders.placeName(URL(fileURLWithPath: "/Volumes/Backup/Scans", isDirectory: true)),
                       "Volumes › Backup › Scans")
    }

    /// The monogram in the About pane: two letters at most, in capitals.
    func testTheMakersInitials() {
        XCTAssertEqual(Maker.initials(of: "Mgrdegh Ghazarian"), "MG")
        XCTAssertEqual(Maker.initials(of: "alejandro buján"), "AB")
        XCTAssertEqual(Maker.initials(of: "  Snapfly "), "S")
        XCTAssertEqual(Maker.initials(of: "Anna Maria Lind"), "AM")
        XCTAssertEqual(Maker.initials(of: ""), "")
    }
}
