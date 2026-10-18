import XCTest
@testable import Tendedero

/// Download, the arrow on the tag: each photo keeps the name it leaves
/// with, numbered as Finder numbers when the folder has one already, and the
/// tag keeps its height with a sixth tool.
final class DownloadsTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/Users/someone/Downloads", isDirectory: true)

    func testAPhotoKeepsItsNameWhenTheFolderHasNoneLikeIt() {
        let url = Downloads.unique("Screenshot 2026-10-18 at 12.00.00.png", in: folder) { _ in false }
        XCTAssertEqual(url.lastPathComponent, "Screenshot 2026-10-18 at 12.00.00.png")
        XCTAssertEqual(url.deletingLastPathComponent().path, folder.path)
    }

    func testANameTakenIsNumberedAsFinderNumbersIt() {
        let taken: Set<String> = ["Image.png", "Image 2.png"]
        let url = Downloads.unique("Image.png", in: folder) { taken.contains($0.lastPathComponent) }
        XCTAssertEqual(url.lastPathComponent, "Image 3.png")
        let bare = Downloads.unique("README", in: folder) { $0.lastPathComponent == "README" }
        XCTAssertEqual(bare.lastPathComponent, "README 2")
    }

    @MainActor
    func testTheTagKeepsItsHeightWithSixTools() {
        XCTAssertEqual(LineTag.rowHeight(tools: 5, clipped: true), 24)
        XCTAssertEqual(LineTag.rowHeight(tools: 5, clipped: false), 22)
        XCTAssertEqual(LineTag.rowHeight(tools: 6, clipped: true), 20)
        XCTAssertEqual(LineTag.rowHeight(tools: 6, clipped: false), 20)
        // On a rope: the clip, the grip's room under it and six tools fit as five did.
        let clip: CGFloat = 26 - 12, grip: CGFloat = 12, bottom: CGFloat = 2
        XCTAssertLessThanOrEqual(clip + grip + 6 * LineTag.rowHeight(tools: 6, clipped: true) + bottom, LineTag.maxHeight)
        XCTAssertLessThanOrEqual(clip + grip + 5 * LineTag.rowHeight(tools: 5, clipped: true) + bottom, LineTag.maxHeight)
        // In a holder, six fit in the room it leaves for them.
        XCTAssertLessThanOrEqual(6 * LineTag.rowHeight(tools: 6, clipped: false) + bottom, Layout.compactToolsHeight)
    }
}
