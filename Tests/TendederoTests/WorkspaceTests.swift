import Foundation
import XCTest
@testable import Tendedero

/// The Workspace's rules: what a folder may be called, how categories
/// change, what is safe to touch, where files go and what deleting would
/// affect. No file outside a temporary folder is ever touched.
final class WorkspaceTests: XCTestCase {
    private var base: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("Workspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: base)
    }

    private func standard() -> WorkspaceConfig {
        .standard(orders: "Orders", customers: "Customers", projects: "Projects", documents: "Documents",
                  other: "Other", unsorted: "Unsorted")
    }

    @discardableResult
    private func file(_ name: String, in folder: URL, bytes: Int = 10) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(count: bytes).write(to: url)
        return url
    }

    // MARK: Names

    func testANameIsMadeSafeForAFolder() {
        XCTAssertEqual(WorkspaceNames.clean("  My / Orders: 2026  "), "My - Orders- 2026")
        XCTAssertEqual(WorkspaceNames.clean("...hidden"), "hidden")
        XCTAssertEqual(WorkspaceNames.clean("a\nb\tc"), "a b c")
        XCTAssertNil(WorkspaceNames.clean("   "))
        XCTAssertNil(WorkspaceNames.clean("..."))
        XCTAssertNil(WorkspaceNames.clean(""))
        let long = String(repeating: "x", count: 200)
        XCTAssertEqual(WorkspaceNames.clean(long)?.count, WorkspaceNames.longest)
    }

    func testNamesAreTheSameIgnoringCaseAndAccents() {
        XCTAssertTrue(WorkspaceNames.same("Orders", "orders"))
        XCTAssertTrue(WorkspaceNames.same("Café", "cafe"))
        XCTAssertFalse(WorkspaceNames.same("Orders", "Order"))
        XCTAssertEqual(WorkspaceNames.unique("Orders", among: ["orders", "Orders 2"]), "Orders 3")
        XCTAssertEqual(WorkspaceNames.unique("New", among: ["Orders"]), "New")
    }

    // MARK: Categories

    func testTheStandardCategoriesEndWithUnsortedWhichIsTheDefault() {
        let config = standard()
        XCTAssertEqual(config.categories.map(\.name), ["Orders", "Customers", "Projects", "Documents", "Other", "Unsorted"])
        XCTAssertEqual(config.defaultCategory.id, WorkspaceCategory.unsortedID)
        XCTAssertEqual(config.visible.count, 6)
    }

    func testACategoryIsAddedRenamedMovedAndHidden() {
        var config = standard()
        let added = config.add("  Returns ")
        XCTAssertEqual(added?.name, "Returns")
        XCTAssertEqual(config.add("orders")?.name, "orders 2")
        XCTAssertNil(config.add("   "))
        let id = added!.id
        // A taken name is refused; its own name in another case is fine.
        XCTAssertNil(config.rename(id, to: "Customers"))
        XCTAssertEqual(config.rename(id, to: "RETURNS"), "Returns")
        XCTAssertEqual(config.category(id)?.name, "RETURNS")
        config.move(id, by: -1)
        XCTAssertEqual(config.categories.firstIndex { $0.id == id }, 5)
        config.move(config.categories[0].id, by: -1)
        XCTAssertEqual(config.categories[0].id, "orders")
        config.setHidden("orders", true)
        XCTAssertEqual(config.visible.count, config.categories.count - 1)
    }

    func testTheDefaultCategoryCannotBeHiddenAndUnsortedCannotBeRemoved() {
        var config = standard()
        config.setDefault("orders")
        config.setHidden("orders", true)
        XCTAssertFalse(config.category("orders")!.hidden)
        XCTAssertNil(config.remove(WorkspaceCategory.unsortedID))
        // Removing the default puts Unsorted back as the default.
        XCTAssertEqual(config.remove("orders")?.name, "Orders")
        XCTAssertEqual(config.defaultID, WorkspaceCategory.unsortedID)
        // Making a hidden category the default shows it.
        config.setHidden("customers", true)
        config.setDefault("customers")
        XCTAssertFalse(config.category("customers")!.hidden)
    }

    func testPathsFollowTheNamesAndAFileFindsItsCategory() {
        var config = standard()
        let desktop = base.appendingPathComponent("Desktop")
        let root = config.root(desktop: desktop)
        XCTAssertEqual(root.lastPathComponent, "Snapfly")
        XCTAssertEqual(root.deletingLastPathComponent().lastPathComponent, "Desktop")
        config.parent = base.appendingPathComponent("Elsewhere").path
        XCTAssertEqual(config.root(desktop: desktop).deletingLastPathComponent().lastPathComponent, "Elsewhere")
        let orders = config.category("orders")!
        let inOrders = config.folder(of: orders, root: root).appendingPathComponent("a.png")
        XCTAssertEqual(config.category(containing: inOrders, root: root)?.id, "orders")
        XCTAssertNil(config.category(containing: root.appendingPathComponent("a.png"), root: root))
        XCTAssertNil(config.category(containing: base.appendingPathComponent("other/a.png"), root: root))
    }

    func testTheSettingsAreKept() throws {
        let suite = UserDefaults(suiteName: "WorkspaceTests-\(UUID().uuidString)")!
        XCTAssertNil(WorkspaceStore.load(suite))
        var config = standard()
        config.setDefault("orders")
        WorkspaceStore.save(config, suite)
        XCTAssertEqual(WorkspaceStore.load(suite), config)
        XCTAssertFalse(WorkspaceStore.isEnabled(suite))
        WorkspaceStore.setEnabled(true, suite)
        XCTAssertTrue(WorkspaceStore.isEnabled(suite))
    }

    // MARK: Safe to touch

    func testNothingOutsideTheFolderIsInsideIt() throws {
        let root = base.appendingPathComponent("Snapfly")
        let inside = try file("a.png", in: root.appendingPathComponent("Orders"))
        XCTAssertTrue(WorkspaceGuard.isInside(inside, of: root))
        XCTAssertFalse(WorkspaceGuard.isInside(root, of: root))
        XCTAssertFalse(WorkspaceGuard.isInside(base.appendingPathComponent("Snapfly2/a.png"), of: root))
        // A link inside that points out is not inside.
        let outside = try file("secret.png", in: base.appendingPathComponent("Outside"))
        let link = root.appendingPathComponent("Orders/link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertFalse(WorkspaceGuard.isInside(link, of: root))
        XCTAssertTrue(WorkspaceGuard.isSymbolicLink(link))
    }

    func testAFolderInTheTrashIsKnownAndTheTopOfTheDiskIsNeverARoot() {
        XCTAssertTrue(WorkspaceGuard.isTrashed(URL(fileURLWithPath: "/Users/me/.Trash/Snapfly")))
        XCTAssertFalse(WorkspaceGuard.isTrashed(URL(fileURLWithPath: "/Users/me/Desktop/Snapfly")))
        let home = URL(fileURLWithPath: "/Users/me")
        let protected = [home, home.appendingPathComponent("Desktop"), home.appendingPathComponent("Documents")]
        XCTAssertFalse(WorkspaceGuard.isSafeRoot(URL(fileURLWithPath: "/"), protected: protected))
        XCTAssertFalse(WorkspaceGuard.isSafeRoot(URL(fileURLWithPath: "/Users"), protected: protected))
        XCTAssertFalse(WorkspaceGuard.isSafeRoot(home, protected: protected))
        XCTAssertFalse(WorkspaceGuard.isSafeRoot(home.appendingPathComponent("Desktop"), protected: protected))
        XCTAssertTrue(WorkspaceGuard.isSafeRoot(home.appendingPathComponent("Desktop/Snapfly"), protected: protected))
        XCTAssertTrue(WorkspaceGuard.isSafeRoot(home.appendingPathComponent("Pictures/Shots"), protected: protected))
    }

    func testTheMarkerIsWrittenOnceAndFound() throws {
        let root = base.appendingPathComponent("Snapfly")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertNil(WorkspaceMarker.read(in: root))
        let first = try WorkspaceMarker.ensure(in: root)
        let second = try WorkspaceMarker.ensure(in: root)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(WorkspaceMarker.read(in: root)?.id, first.id)
    }

    // MARK: Files

    func testANameIsNeverTakenTwice() throws {
        let folder = base.appendingPathComponent("F")
        let first = try file("Shot.png", in: folder)
        XCTAssertEqual(WorkspaceFiles.unique("Shot.png", in: folder).lastPathComponent, "Shot 2.png")
        try file("Shot 2.png", in: folder)
        XCTAssertEqual(WorkspaceFiles.unique("Shot.png", in: folder).lastPathComponent, "Shot 3.png")
        XCTAssertEqual(WorkspaceFiles.unique("New.png", in: folder).lastPathComponent, "New.png")
        XCTAssertEqual(WorkspaceFiles.unique("README", in: folder).lastPathComponent, "README")
        XCTAssertNil(WorkspaceFiles.destination(of: first, into: folder))
    }

    func testAMoveKeepsEveryFileAndReplacesNone() throws {
        let from = base.appendingPathComponent("A"), to = base.appendingPathComponent("B")
        let one = try file("Shot.png", in: from, bytes: 5)
        try file("Shot.png", in: to, bytes: 7)
        let moved = try WorkspaceFiles.move(one, into: to)
        XCTAssertEqual(moved.lastPathComponent, "Shot 2.png")
        XCTAssertFalse(FileManager.default.fileExists(atPath: one.path))
        // The one already there is untouched.
        XCTAssertEqual(try Data(contentsOf: to.appendingPathComponent("Shot.png")).count, 7)
        XCTAssertEqual(try Data(contentsOf: moved).count, 5)
        // Moving into the folder it is in does nothing.
        XCTAssertEqual(try WorkspaceFiles.move(moved, into: to), moved)
    }

    func testOnlyScreenshotsAreListedNewestFirstAndOthersAreLeftAlone() throws {
        let folder = base.appendingPathComponent("F")
        let old = try file("old.png", in: folder, bytes: 3)
        let new = try file("new.PDF", in: folder, bytes: 4)
        try file("notes.txt", in: folder)
        try file(".hidden.png", in: folder)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.creationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: new.path)
        let items = WorkspaceFiles.items(in: folder)
        XCTAssertEqual(items.map { $0.url.lastPathComponent }, ["new.PDF", "old.png"])
        XCTAssertEqual(items.map(\.size), [4, 3])
        XCTAssertEqual(WorkspaceFiles.others(in: folder).map(\.lastPathComponent), ["notes.txt"])
    }

    // MARK: Counting and removing

    func testEachCategoryIsCounted() throws {
        let config = standard()
        let root = base.appendingPathComponent("Snapfly")
        try file("a.png", in: root.appendingPathComponent("Orders"), bytes: 10)
        try file("b.png", in: root.appendingPathComponent("Orders"), bytes: 20)
        try file("c.mov", in: root.appendingPathComponent("Unsorted"), bytes: 5)
        let tallies = WorkspaceStats.scan(config, root: root)
        XCTAssertEqual(tallies["orders"], WorkspaceTally(count: 2, bytes: 30))
        XCTAssertEqual(tallies["unsorted"], WorkspaceTally(count: 1, bytes: 5))
        XCTAssertEqual(tallies["customers"], WorkspaceTally())
        XCTAssertEqual(WorkspaceStats.total(tallies), WorkspaceTally(count: 3, bytes: 35))
    }

    func testRemovingTheWorkspaceNamesWhatGoesAndKeepsWhatIsNotSnapflys() throws {
        let config = standard()
        let root = base.appendingPathComponent("Snapfly")
        try WorkspaceMarker.ensure(in: { try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root }())
        try file("a.png", in: root.appendingPathComponent("Orders"))
        try file("b.png", in: root.appendingPathComponent("Unsorted"), bytes: 5)
        try file("mine.txt", in: root.appendingPathComponent("Orders"))
        try file("stray.docx", in: root)
        let plan = WorkspaceRemoval.plan(config, root: root)
        XCTAssertEqual(Set(plan.files.map(\.lastPathComponent)), ["a.png", "b.png"])
        // Orders has a file of somebody's own, so it stays; so does the root.
        XCTAssertEqual(Set(plan.left.map(\.lastPathComponent)), ["mine.txt", "stray.docx"])
        XCTAssertEqual(plan.folders.map(\.lastPathComponent), ["Unsorted"])
        XCTAssertEqual(plan.bytes, 15)
    }

    func testAnUntouchedWorkspaceCanGoWhole() throws {
        let config = standard()
        let root = base.appendingPathComponent("Snapfly")
        try file("a.png", in: root.appendingPathComponent("Orders"))
        let plan = WorkspaceRemoval.plan(config, root: root)
        XCTAssertTrue(plan.left.isEmpty)
        XCTAssertEqual(plan.folders.last?.lastPathComponent, "Snapfly")
        XCTAssertEqual(plan.files.count, 1)
    }

    // MARK: Where, for any thread

    func testTheLocationIsSetAndCleared() {
        XCTAssertNil(WorkspaceLocation.value)
        let root = base.appendingPathComponent("Snapfly")
        WorkspaceLocation.set(root: root, landing: root.appendingPathComponent("Unsorted"))
        XCTAssertEqual(WorkspaceLocation.value?.landing.lastPathComponent, "Unsorted")
        WorkspaceLocation.set(root: nil, landing: nil)
        XCTAssertNil(WorkspaceLocation.value)
    }
}
