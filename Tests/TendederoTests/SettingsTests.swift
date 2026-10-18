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

    func testTheIconsStandInRowsOfTheSameLength() {
        // Eighteen that fit sixteen to a row go nine and nine, not sixteen and two.
        XCTAssertEqual(IconGrid.perRow(count: 18, fitting: 16), 9)
        // Seventeen go nine and eight.
        XCTAssertEqual(IconGrid.perRow(count: 17, fitting: 16), 9)
        // Where all fit, they stay in one row.
        XCTAssertEqual(IconGrid.perRow(count: 18, fitting: 18), 18)
        XCTAssertEqual(IconGrid.perRow(count: 18, fitting: 25), 18)
        // Narrower, three even rows of six.
        XCTAssertEqual(IconGrid.perRow(count: 18, fitting: 8), 6)
        // Never none to a row.
        XCTAssertEqual(IconGrid.perRow(count: 18, fitting: 0), 1)
        XCTAssertEqual(IconGrid.perRow(count: 0, fitting: 10), 1)
    }
}
