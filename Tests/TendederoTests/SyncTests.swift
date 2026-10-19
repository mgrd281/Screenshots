import Foundation
import XCTest
@testable import Tendedero

/// Syncing's rules without iCloud: the order of changes, merging, versions
/// two devices made at once, removals, the changes waiting to go, what may
/// leave the device, the status, and the file it is kept in. Two ledgers
/// stand for a Mac and an iPhone, and `deliver` for iCloud between them.
final class SyncTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var on: SyncSettings {
        var settings = SyncSettings()
        settings.on = true
        return settings
    }

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    /// Sends what may go from one device and applies it on the other, as
    /// iCloud would; returns what applying asked of the receiver.
    @discardableResult
    private func deliver(from sender: inout SyncLedger, to receiver: inout SyncLedger,
                         settings: SyncSettings? = nil, now: Date? = nil) -> [SyncLedger.Effect] {
        let settings = settings ?? on
        var effects: [SyncLedger.Effect] = []
        for operation in sender.due(now: now ?? at(10_000)) where SyncPolicy.allows(operation, in: sender, settings: settings) {
            sender.markSending(operation.key)
            if operation.kind == .purge {
                effects += receiver.applyDeletion(operation.key)
            } else if operation.key.kind != .file, let record = sender.record(for: operation.key) {
                // Through the payload, as iCloud carries it.
                guard case .record(let carried) = SyncRecord.decode(operation.key.kind, payload: try! record.payload()) else {
                    XCTFail("\(operation.key.recordName) did not survive the trip")
                    continue
                }
                effects += receiver.apply(carried, now: now ?? at(10_000))
            }
            sender.markDone(operation.key)
        }
        return effects
    }

    private func mac() -> SyncLedger { SyncLedger(device: "A-mac") }
    private func phone() -> SyncLedger { SyncLedger(device: "B-phone") }

    @discardableResult
    private func shot(_ ledger: inout SyncLedger, _ hash: String = "h1", content: SyncRevision.Content = .protected,
                      at seconds: TimeInterval = 0) -> String {
        ledger.add(name: "Screenshot.png", file: "/tmp/\(hash).png", hash: hash, bytes: 1000, content: content,
                   created: at(seconds), now: at(seconds)).screenshot
    }

    // MARK: Order of changes

    func testStampsFromOneDeviceAlwaysRise() {
        var clock = SyncClock(device: "A")
        let first = clock.tick(now: start)
        let second = clock.tick(now: start)
        let third = clock.tick(now: start.addingTimeInterval(-5))
        XCTAssertLessThan(first, second)
        XCTAssertLessThan(second, third, "a clock set back does not make an earlier stamp")
    }

    func testAChangeAfterSeeingAnotherComesAfterItEvenWithASlowClock() {
        var slow = SyncClock(device: "A")
        let remote = SyncStamp(millis: Int64(start.timeIntervalSince1970 * 1000) + 60_000, counter: 3, device: "Z")
        slow.saw(remote)
        XCTAssertGreaterThan(slow.tick(now: start), remote)
    }

    func testTheSameMomentIsDecidedByTheDevice() {
        let a = SyncStamp(millis: 5, counter: 0, device: "A")
        let b = SyncStamp(millis: 5, counter: 0, device: "B")
        XCTAssertLessThan(a, b)
        let one = SyncField(value: "one", stamp: a), two = SyncField(value: "two", stamp: b)
        XCTAssertEqual(one.merged(with: two), two.merged(with: one))
    }

    func testPermanentRemovalStaysWhateverCameLater() {
        let early = SyncStamp(millis: 1, counter: 0, device: "A"), late = SyncStamp(millis: 9, counter: 0, device: "B")
        let permanent = SyncField(value: SyncRemoval.permanent, stamp: early)
        let restored = SyncField(value: SyncRemoval.none, stamp: late)
        XCTAssertEqual(permanent.mergedRemoval(with: restored).value, .permanent)
        XCTAssertEqual(restored.mergedRemoval(with: permanent).value, .permanent)
    }

    // MARK: Records

    func testRecordNamesGoBothWays() {
        let key = SyncKey(.screenshot, "6F1C-AA")
        XCTAssertEqual(key.recordName, "Screenshot.6F1C-AA")
        XCTAssertEqual(SyncKey(recordName: "Screenshot.6F1C-AA"), key)
        XCTAssertEqual(SyncKey(recordName: "Revision.a.b")?.id, "a.b")
        XCTAssertNil(SyncKey(recordName: "Nonsense.1"))
        XCTAssertNil(SyncKey(recordName: "Device."))
    }

    func testARecordFromANewerSnapflyIsLeftAlone() throws {
        let envelope = #"{"schema":2,"body":"e30="}"#.data(using: .utf8)!
        XCTAssertEqual(SyncRecord.decode(.screenshot, payload: envelope), .tooNew(schema: 2))
        XCTAssertEqual(SyncRecord.decode(.screenshot, payload: Data("x".utf8)), .unreadable)
    }

    func testFieldsAnOlderSnapflyDoesNotKnowAreSkipped() throws {
        var ledger = mac()
        let id = shot(&ledger)
        let record = try XCTUnwrap(ledger.record(for: SyncKey(.screenshot, id)))
        var body = try JSONSerialization.jsonObject(with: SyncCoding.encoder.encode(ledger.screenshots[id]!)) as! [String: Any]
        body["somethingNew"] = ["a": 1]
        let envelope = try JSONSerialization.data(withJSONObject: [
            "schema": SyncSchema.current, "body": try JSONSerialization.data(withJSONObject: body).base64EncodedString(),
        ])
        XCTAssertEqual(SyncRecord.decode(.screenshot, payload: envelope), .record(record))
    }

    // MARK: Adding and merging

    func testTheSamePictureTwiceIsOneScreenshot() {
        var ledger = mac()
        let first = ledger.add(name: "a.png", file: "/a", hash: "same", bytes: 1, content: .original, created: start)
        let again = ledger.add(name: "b.png", file: "/b", hash: "same", bytes: 1, content: .original, created: start)
        XCTAssertTrue(first.isNew)
        XCTAssertFalse(again.isNew)
        XCTAssertEqual(first.screenshot, again.screenshot)
        XCTAssertEqual(ledger.screenshots.count, 1)
    }

    func testAMacScreenshotArrivesOnTheIPhone() {
        var a = mac(), b = phone()
        let id = shot(&a)
        deliver(from: &a, to: &b)
        XCTAssertEqual(b.visible.map(\.id), [id])
        XCTAssertEqual(b.current(of: id)?.content, .protected)
        XCTAssertNil(b.local[b.current(of: id)!.id], "only the preview comes; the picture when opened")
        XCTAssertTrue(a.journal.isEmpty)
    }

    func testTheSameRecordTwiceChangesNothing() throws {
        var a = mac(), b = phone()
        let id = shot(&a)
        let record = try XCTUnwrap(a.record(for: SyncKey(.screenshot, id)))
        b.apply(record)
        let once = b
        b.apply(record)
        XCTAssertEqual(b, once)
        XCTAssertTrue(b.journal.isEmpty, "nothing to send back")
    }

    func testMovesOnBothDevicesEndTheSameWhicheverArrivesFirst() {
        var a = mac(), b = phone()
        let id = shot(&a)
        deliver(from: &a, to: &b)
        a.move(id, to: "orders", now: at(100))
        b.move(id, to: "customers", now: at(101))
        var a2 = a, b2 = b
        deliver(from: &a, to: &b)
        deliver(from: &b, to: &a)
        deliver(from: &b2, to: &a2)
        deliver(from: &a2, to: &b2)
        for ledger in [a, b, a2, b2] {
            XCTAssertEqual(ledger.screenshots[id]?.project.value, "customers", "the later move stays")
        }
    }

    func testTwoDevicesChangingOneScreenshotKeepBothVersions() throws {
        var a = mac(), b = phone()
        let id = shot(&a)
        deliver(from: &a, to: &b)
        let fromMac = try XCTUnwrap(a.addRevision(to: id, change: .covered, content: .protected,
                                                  fileName: "m.png", file: "/m", hash: "mac", bytes: 1, now: at(50)))
        let fromPhone = try XCTUnwrap(b.addRevision(to: id, change: .edited, content: .protected,
                                                    fileName: "p.png", file: "/p", hash: "phone", bytes: 1, now: at(51)))
        let onPhone = deliver(from: &a, to: &b)
        deliver(from: &b, to: &a)
        XCTAssertEqual(onPhone, [.conflict(id)])
        for ledger in [a, b] {
            XCTAssertEqual(Set(ledger.heads(of: id).map(\.id)), [fromMac, fromPhone])
            XCTAssertNil(ledger.current(of: id), "no version wins by itself")
            XCTAssertEqual(ledger.conflicts.map(\.id), [id])
        }
    }

    func testChoosingAVersionSetsTheOtherAsideOnEveryDevice() throws {
        var a = mac(), b = phone()
        let id = shot(&a)
        deliver(from: &a, to: &b)
        let kept = try XCTUnwrap(a.addRevision(to: id, change: .covered, content: .protected,
                                               fileName: "m", file: "/m", hash: "mac", bytes: 1, now: at(50)))
        let other = try XCTUnwrap(b.addRevision(to: id, change: .edited, content: .protected,
                                                fileName: "p", file: "/p", hash: "phone", bytes: 1, now: at(51)))
        deliver(from: &a, to: &b)
        deliver(from: &b, to: &a)
        // A third copy that has not heard of the choice yet.
        var away = b
        b.choose(kept, now: at(60))
        deliver(from: &b, to: &a)
        for ledger in [a, b] {
            XCTAssertEqual(ledger.current(of: id)?.id, kept)
            XCTAssertNotNil(ledger.revisions[other], "set aside, not deleted")
        }
        // Changed again on the version set aside: the owner is asked again.
        let later = try XCTUnwrap(away.addRevision(to: id, change: .edited, content: .protected, fileName: "q",
                                                   file: "/q", hash: "later", bytes: 1, now: at(70)))
        XCTAssertEqual(away.revisions[later]?.parent, other)
        XCTAssertEqual(deliver(from: &away, to: &a), [.conflict(id)])
        XCTAssertEqual(Set(a.heads(of: id).map(\.id)), [kept, later])
    }

    func testANewVersionHereReplacesTheOneShown() throws {
        var a = mac()
        let id = shot(&a, content: .original)
        let covered = try XCTUnwrap(a.addRevision(to: id, change: .covered, content: .protected,
                                                  fileName: "c", file: "/c", hash: "c", bytes: 1, now: at(5)))
        let again = try XCTUnwrap(a.addRevision(to: id, change: .covered, content: .protected,
                                                fileName: "c2", file: "/c2", hash: "c2", bytes: 1, now: at(6)))
        XCTAssertEqual(a.revisions[again]?.parent, covered)
        XCTAssertEqual(a.current(of: id)?.id, again)
    }

    // MARK: Removing

    func testARemovedScreenshotDoesNotComeBackFromADeviceThatWasAway() throws {
        var a = mac(), b = phone()
        let id = shot(&a)
        deliver(from: &a, to: &b)
        b.rename(id, to: "Renamed while away", now: at(20))
        let files = a.remove(id, .workspace, now: at(30))
        XCTAssertEqual(files.count, 1)
        deliver(from: &b, to: &a)
        let effects = deliver(from: &a, to: &b)
        XCTAssertTrue(a.visible.isEmpty)
        XCTAssertTrue(b.visible.isEmpty)
        XCTAssertEqual(b.screenshots[id]?.name.value, "Renamed while away", "the rename is kept, removed")
        XCTAssertTrue(effects.isEmpty, "the iPhone had only a preview, no file to remove")
    }

    func testAVersionMadeLaterBringsAWorkspaceRemovalBack() throws {
        var a = mac(), b = phone()
        let id = shot(&a)
        deliver(from: &a, to: &b)
        a.remove(id, .workspace, now: at(30))
        b.addRevision(to: id, change: .edited, content: .protected, fileName: "p", file: "/p", hash: "late", bytes: 1,
                      now: at(40))
        deliver(from: &a, to: &b)
        deliver(from: &b, to: &a)
        XCTAssertEqual(a.visible.map(\.id), [id], "an edit made afterwards is not lost")
        XCTAssertEqual(b.visible.map(\.id), [id])
    }

    func testPermanentRemovalTakesThePicturesOutAndNothingBringsItBack() throws {
        var a = mac(), b = phone()
        let id = shot(&a)
        let version = try XCTUnwrap(a.current(of: id)?.id)
        deliver(from: &a, to: &b)
        a.remove(id, .permanent, now: at(30))
        XCTAssertTrue(a.journal.contains { $0.kind == .purge && $0.key == SyncKey(.file, version) })
        deliver(from: &a, to: &b)
        XCTAssertNil(b.revisions[version])
        XCTAssertTrue(b.visible.isEmpty)
        a.restore(id, now: at(40))
        XCTAssertTrue(a.visible.isEmpty, "permanent cannot be undone")
    }

    func testRemovalsLeaveICloudAfterThirtyDays() {
        var a = mac(), b = phone()
        let id = shot(&a)
        deliver(from: &a, to: &b)
        a.remove(id, .workspace, now: at(30))
        deliver(from: &a, to: &b)
        a.purgeOld(now: at(30 + SyncLedger.keepRemoved - 60))
        XCTAssertFalse(a.journal.contains { $0.kind == .purge }, "not before thirty days")
        a.purgeOld(now: at(31 + SyncLedger.keepRemoved))
        XCTAssertTrue(a.journal.contains { $0.kind == .purge && $0.key == SyncKey(.screenshot, id) })
        deliver(from: &a, to: &b, now: at(32 + SyncLedger.keepRemoved))
        XCTAssertNil(a.screenshots[id])
        XCTAssertNil(b.screenshots[id])
        XCTAssertTrue(b.revisions.isEmpty)
    }

    func testRemovingAProjectMovesItsScreenshotsToUnsorted() {
        var a = mac()
        a.setProject("orders", name: "Orders", order: 0, now: at(0))
        a.setProject(SyncProject.unsortedID, name: "Unsorted", order: 5, now: at(0))
        let id = shot(&a)
        a.move(id, to: "orders", now: at(1))
        a.removeProject("orders", now: at(2))
        a.removeProject(SyncProject.unsortedID, now: at(3))
        XCTAssertEqual(a.screenshots[id]?.project.value, SyncProject.unsortedID)
        XCTAssertFalse(a.projects[SyncProject.unsortedID]!.removed.value, "Unsorted stays")
    }

    // MARK: Waiting to go

    func testOneChangePerRecordWaits() {
        var a = mac()
        let key = SyncKey(.screenshot, "x")
        a.enqueue(.save, key, now: at(0))
        a.enqueue(.save, key, now: at(1))
        XCTAssertEqual(a.journal.count, 1)
        a.enqueue(.purge, key, now: at(2))
        a.enqueue(.save, key, now: at(3))
        XCTAssertEqual(a.journal.map(\.kind), [.purge], "taking it out for good wins")
    }

    func testAChangeMadeWhileSendingGoesOnceMore() {
        var a = mac()
        let key = SyncKey(.project, "orders")
        a.enqueue(.save, key)
        a.markSending(key)
        a.enqueue(.save, key)
        a.markDone(key)
        XCTAssertEqual(a.journal.map(\.state), [.waiting])
        a.markDone(key)
        XCTAssertTrue(a.journal.isEmpty)
    }

    func testRetriesWaitLongerEachTimeUpToAnHour() {
        XCTAssertEqual(SyncRetry.delay(after: 1), 30)
        XCTAssertEqual(SyncRetry.delay(after: 2), 60)
        XCTAssertEqual(SyncRetry.delay(after: 3), 120)
        XCTAssertEqual(SyncRetry.delay(after: 20), 3600)
        XCTAssertEqual(SyncRetry.delay(after: 1, retryAfter: 90), 90, "as long as iCloud asked")
    }

    func testAChangeThatKeepsFailingStopsAndWaitsForTheOwner() {
        var a = mac()
        let key = SyncKey(.project, "orders")
        a.enqueue(.save, key, now: at(0))
        for attempt in 1...SyncRetry.attempts {
            a.markFailed(key, .other("server"), now: at(TimeInterval(attempt)))
        }
        XCTAssertEqual(a.journal.first?.state, .stuck)
        XCTAssertTrue(a.due(now: at(1_000_000)).isEmpty, "no endless retrying")
        a.retryStuck()
        XCTAssertEqual(a.due(now: at(0)).map(\.key), [key])
    }

    func testBeingOfflineIsNotAFailure() {
        var a = mac()
        let key = SyncKey(.project, "orders")
        a.enqueue(.save, key, now: at(0))
        for _ in 0..<50 { a.markFailed(key, .offline, now: at(1)) }
        XCTAssertEqual(a.journal.first?.attempts, 0)
        XCTAssertEqual(a.journal.first?.state, .waiting)
    }

    func testAFailureWaitsBeforeTryingAgain() {
        var a = mac()
        let key = SyncKey(.project, "orders")
        a.enqueue(.save, key, now: at(0))
        a.markFailed(key, .busy(retryAfter: nil), now: at(0))
        XCTAssertTrue(a.due(now: at(10)).isEmpty)
        XCTAssertEqual(a.due(now: at(31)).map(\.key), [key])
    }

    func testSmallRecordsGoBeforePictures() {
        var a = mac()
        shot(&a)
        a.setProject("orders", name: "Orders", order: 0)
        XCTAssertEqual(a.due().map(\.key.kind), [.project, .screenshot, .revision, .file])
    }

    func testAfterAQuitWhatWasBeingSentWaitsAgain() {
        var a = mac()
        let key = SyncKey(.project, "orders")
        a.enqueue(.save, key)
        a.markSending(key)
        a.resume()
        XCTAssertEqual(a.journal.first?.state, .waiting)
    }

    // MARK: What may leave the device

    func testNothingLeavesWhileSyncingIsOff() {
        var a = mac()
        shot(&a)
        XCTAssertTrue(SyncPolicy.waiting(in: a, settings: SyncSettings()).isEmpty)
    }

    func testAnOriginalStaysUnlessTheOwnerChoseOriginals() throws {
        var a = mac()
        let id = shot(&a, "orig", content: .original, at: 10)
        let original = try XCTUnwrap(a.current(of: id))
        XCTAssertFalse(SyncPolicy.picture(original, in: a, settings: on))
        XCTAssertFalse(SyncPolicy.allows(SyncKey(.screenshot, id), kind: .save, in: a, settings: on),
                       "a screenshot with nothing that may go is not even named in iCloud")
        var originals = on
        originals.setOriginals(true, now: at(5))
        XCTAssertTrue(SyncPolicy.picture(original, in: a, settings: originals))
        originals.setOriginals(true, now: at(20))
        XCTAssertFalse(SyncPolicy.picture(original, in: a, settings: originals), "older originals stay unasked")
    }

    func testTheCoveredCopyGoesAndTheOriginalStays() throws {
        var a = mac(), b = phone()
        let id = shot(&a, "orig", content: .original)
        let covered = try XCTUnwrap(a.addRevision(to: id, change: .covered, content: .protected,
                                                  redaction: SyncRedaction(kinds: ["iban"], areas: 2, look: "ink"),
                                                  fileName: "c", file: "/c", hash: "c", bytes: 1, now: at(5)))
        deliver(from: &a, to: &b)
        XCTAssertEqual(Array(b.revisions.keys), [covered])
        XCTAssertEqual(b.current(of: id)?.redaction?.kinds, ["iban"])
        XCTAssertFalse(a.journal.isEmpty, "the original's records wait, held back")
    }

    func testAProjectThatDoesNotSyncKeepsItsScreenshots() {
        var a = mac()
        a.setProject("private", name: "Private", order: 0, syncs: false)
        let id = shot(&a)
        a.move(id, to: "private")
        XCTAssertFalse(SyncPolicy.picture(a.current(of: id)!, in: a, settings: on))
    }

    func testAnotherDevicesVersionsAreNeverSentFromHere() {
        var a = mac(), b = phone()
        let id = shot(&a)
        deliver(from: &a, to: &b)
        XCTAssertFalse(SyncPolicy.picture(b.current(of: id)!, in: b, settings: on))
    }

    func testTooLargeStaysHere() {
        var a = mac()
        let id = a.add(name: "big", file: "/big", hash: "big", bytes: SyncPolicy.largestFile + 1, content: .protected,
                       created: start).screenshot
        XCTAssertFalse(SyncPolicy.picture(a.current(of: id)!, in: a, settings: on))
    }

    func testTurningOnQueuesWhatThisDeviceMadeAndICloudLacks() {
        var a = mac()
        shot(&a)
        a.journal = []
        a.queueUnsent()
        XCTAssertEqual(Set(a.journal.map(\.key.kind)), [.screenshot, .revision, .file])
    }

    // MARK: Devices and accounts

    func testADeviceSaysItIsThereAtMostHourly() {
        var a = mac()
        let device = SyncDevice(id: a.deviceID, name: "Mac", platform: .mac, model: "Mac15,3", registered: start,
                                lastSeen: start, lastSync: nil, appVersion: "1.1.0", schema: SyncSchema.current)
        a.register(device, now: at(0))
        a.markDone(SyncKey(.device, a.deviceID))
        a.register(device, now: at(600))
        XCTAssertTrue(a.journal.isEmpty)
        a.register(device, now: at(3700))
        XCTAssertEqual(a.journal.map(\.key.kind), [.device])
        var renamed = device
        renamed.name = "Studio"
        a.markDone(SyncKey(.device, a.deviceID))
        a.register(renamed, now: at(3800))
        XCTAssertEqual(a.journal.map(\.key.kind), [.device])
    }

    func testOtherDevicesAppearAndOnlyEachWritesItsOwn() {
        var a = mac(), b = phone()
        let phoneDevice = SyncDevice(id: b.deviceID, name: "iPhone", platform: .iPhone, model: "iPhone16,1",
                                     registered: start, lastSeen: start, lastSync: nil, appVersion: "1.1.0",
                                     schema: SyncSchema.current)
        b.register(phoneDevice, now: at(0))
        deliver(from: &b, to: &a)
        XCTAssertEqual(a.devices[b.deviceID]?.name, "iPhone")
        XCTAssertTrue(a.devices[b.deviceID]!.isPresent(now: at(60)))
        XCTAssertFalse(a.devices[b.deviceID]!.isPresent(now: at(3600)))
        var stranger = phoneDevice
        stranger.id = a.deviceID
        a.apply(.device(stranger))
        XCTAssertNil(a.devices[a.deviceID], "nobody else writes this device's record")
    }

    func testAnotherAccountTakesWhatCameFromTheOldOneAndKeepsWhatWasMadeHere() {
        var a = mac(), b = phone()
        let mine = shot(&b, "mine")
        let theirs = shot(&a, "theirs")
        deliver(from: &a, to: &b)
        deliver(from: &b, to: &a)
        b.local[b.current(of: theirs)!.id] = SyncLocal(file: "/fetched")
        let fetched = b.current(of: theirs)!.id
        let gone = b.forgetAccount()
        XCTAssertEqual(gone, [fetched])
        XCTAssertNil(b.screenshots[theirs])
        XCTAssertNotNil(b.screenshots[mine])
        XCTAssertTrue(b.onServer.isEmpty)
        b.queueUnsent()
        XCTAssertTrue(b.journal.contains { $0.key == SyncKey(.screenshot, mine) })
    }

    func testAnUpdateIsAskedForWhenAnotherDeviceIsNewer() {
        var a = mac()
        a.noteTooNew(SyncKey(.screenshot, "x"))
        XCTAssertEqual(SyncState.of(a, settings: on, account: .available, online: true, busy: false, lastSync: nil),
                       .attention(.needsUpdate))
    }

    // MARK: Status

    func testTheStatusSaysWhatIsGoingOn() {
        var a = mac()
        XCTAssertEqual(SyncState.of(a, settings: SyncSettings(), account: .available, online: true, busy: false,
                                    lastSync: nil), .off)
        XCTAssertEqual(SyncState.of(a, settings: on, account: .none, online: true, busy: false, lastSync: nil),
                       .unavailable(.noAccount))
        XCTAssertEqual(SyncState.of(a, settings: on, account: .available, online: true, busy: false, lastSync: start),
                       .upToDate(start))
        shot(&a)
        XCTAssertEqual(SyncState.of(a, settings: on, account: .available, online: false, busy: false, lastSync: nil),
                       .waitingForNetwork(waiting: 3))
        XCTAssertEqual(SyncState.of(a, settings: on, account: .available, online: true, busy: true, lastSync: nil),
                       .syncing(waiting: 3))
        let key = SyncKey(.revision, a.current(of: a.visible[0].id)!.id)
        a.markFailed(key, .iCloudFull)
        XCTAssertEqual(SyncState.of(a, settings: on, account: .available, online: true, busy: false, lastSync: nil),
                       .attention(.iCloudFull))
        XCTAssertEqual(SyncState.of(a, settings: on, account: .available, online: true, busy: false, lastSync: nil,
                                    problem: .notInThisBuild), .unavailable(.notInThisBuild))
    }

    // MARK: The file

    func testTheLedgerIsKeptAndReadBack() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Ledger.json")
        XCTAssertEqual(SyncLedgerFile.load(url, device: "A").outcome, .fresh)
        var a = mac()
        shot(&a)
        a.markSending(a.journal[0].key)
        a.engineState = Data([1, 2, 3])
        try SyncLedgerFile.save(a, to: url)
        let (read, outcome) = SyncLedgerFile.load(url, device: "ignored")
        XCTAssertEqual(outcome, .loaded)
        XCTAssertEqual(read.deviceID, a.deviceID)
        XCTAssertEqual(read.screenshots, a.screenshots)
        XCTAssertEqual(read.engineState, Data([1, 2, 3]))
        XCTAssertFalse(read.journal.contains { $0.state == .sending }, "sending is waiting again")
    }

    func testAFileFromANewerSnapflyIsLeftAsItIs() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Ledger.json")
        let newer = Data(#"{"version":99,"clock":{"device":"A"}}"#.utf8)
        try newer.write(to: url)
        XCTAssertEqual(SyncLedgerFile.load(url, device: "A").outcome, .newer(99))
        XCTAssertEqual(try Data(contentsOf: url), newer)
    }

    func testAnUnreadableFileIsSetAsideNotOverwritten() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Ledger.json")
        try Data("not json".utf8).write(to: url)
        let (ledger, outcome) = SyncLedgerFile.load(url, device: "A")
        guard case .unreadable(let aside?) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(aside)), Data("not json".utf8))
        XCTAssertTrue(ledger.screenshots.isEmpty)
    }

    func testAnOlderFileWithoutLaterFieldsStillOpens() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Ledger.json")
        try Data(#"{"version":1,"clock":{"device":"A"}}"#.utf8).write(to: url)
        let (ledger, outcome) = SyncLedgerFile.load(url, device: "B")
        XCTAssertEqual(outcome, .loaded)
        XCTAssertEqual(ledger.deviceID, "A")
    }

    func testTheSettingsAreKeptAndOffAtFirst() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "SyncTests-\(UUID().uuidString)"))
        XCTAssertFalse(SyncSettings.load(from: defaults).on)
        var settings = on
        settings.setOriginals(true, now: start)
        settings.save(to: defaults)
        XCTAssertEqual(SyncSettings.load(from: defaults), settings)
        let id = SyncSettings.deviceID(in: defaults)
        XCTAssertEqual(SyncSettings.deviceID(in: defaults), id, "made once")
    }
}
