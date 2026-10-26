#if canImport(CloudKit)
import CloudKit
import Combine
import Foundation

/// Pairing with a code, for a Mac and a device on different Apple accounts
/// (SYNC.md, "Pairing with a code"). The two meet in iCloud's public
/// database, in records named from the code and sealed with it: the Mac
/// shows the code, the device that types it asks to join, and the person at
/// the Mac says yes or no. On yes the Mac shares its zones with that
/// device's account alone; the records come down again within minutes.
enum PairingCloud {
    static let recordType = "Pairing"
    /// How long a device waits for the person at the Mac.
    static let answerWait: TimeInterval = 180

    static var container: CKContainer? {
        CloudSetup.container.map { CKContainer(identifier: $0) }
    }

    static func record(_ name: String, payload: Data) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: name))
        record["payload"] = payload as NSData
        return record
    }

    static func payload(_ record: CKRecord) -> Data? {
        record["payload"] as? Data
    }

    /// Saves one record and says whether iCloud took it.
    static func save(_ record: CKRecord, in database: CKDatabase) async throws {
        let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys,
                                                          atomically: false)
        _ = try saved[record.recordID]?.get()
    }

    /// Takes records down; ones already gone are no matter.
    static func remove(_ names: [String], from database: CKDatabase) async {
        guard !names.isEmpty else { return }
        _ = try? await database.modifyRecords(saving: [], deleting: names.map { CKRecord.ID(recordName: $0) },
                                              savePolicy: .allKeys, atomically: false)
    }

    static func isOffline(_ error: Error) -> Bool {
        guard let error = error as? CKError else { return false }
        return [.networkUnavailable, .networkFailure, .serviceUnavailable].contains(error.code)
    }
}

/// The Mac's side: a code on screen, a new one every 30 seconds, and a
/// question when a device typed it.
@MainActor
final class PairingHost: ObservableObject {
    enum Step: Equatable {
        case showing
        /// A device typed the code and asks to join.
        case asking(PairingMessage.Request)
        case sharing(String)
        case joined(String)
        case sameAccount(String)
        case failed(String)
    }

    @Published private(set) var schedule = PairingSchedule()
    @Published private(set) var step = Step.showing
    @Published private(set) var now = Date()

    private let sync: SyncCenter
    private let name: String
    private var task: Task<Void, Never>?
    /// Sharing with the device let in, which the sheet's Cancel stops.
    private var sharing: Task<Void, Never>?
    private var database: CKDatabase?
    /// The offer records up, by code.
    private var offered: [String: String] = [:]
    /// Requests already asked about, so each is asked once.
    private var seen: Set<String> = []
    private var asking: (request: PairingMessage.Request, code: String)?

    init(sync: SyncCenter = .shared, name: String) {
        self.sync = sync
        self.name = name
    }

    func begin() {
        end()
        guard let container = PairingCloud.container else {
            step = .failed(SyncProblem.notInThisBuild.text)
            return
        }
        guard sync.canShare else {
            step = .failed(L("Turn on syncing on this Mac first, then try again."))
            return
        }
        database = container.publicCloudDatabase
        schedule = PairingSchedule()
        step = .showing
        seen = []
        asking = nil
        task = Task { [weak self] in await self?.run() }
    }

    /// The sheet closed: the code stops working at once, and sharing still
    /// under way stops too.
    func end() {
        task?.cancel()
        task = nil
        sharing?.cancel()
        sharing = nil
        if let database { Task { [names = Array(offered.values)] in await PairingCloud.remove(names, from: database) } }
        offered = [:]
    }

    /// The person at the Mac lets the device in.
    func accept() {
        guard case .asking(let request) = step, let asking else { return }
        step = .sharing(request.device.name)
        sharing = Task {
            if request.user == sync.account {
                await answer(.init(outcome: .sameAccount, name: name, owner: sync.account), code: asking.code)
                step = .sameAccount(request.device.name)
                return
            }
            // Let in by an earlier pairing, the account stays in should this one be cancelled.
            let known = await sync.shares(with: request.user)
            do {
                let links = try await sync.invite(request.user)
                // Cancelled meanwhile: the device hears no, and is sent
                // nothing it could join with.
                guard !Task.isCancelled else { return withdraw(request.user, known: known, code: asking.code) }
                await answer(.init(outcome: .joined, shares: links, name: name, owner: sync.account), code: asking.code)
                step = .joined(request.device.name)
            } catch {
                guard !Task.isCancelled else { return withdraw(request.user, known: known, code: asking.code) }
                log.error("Sharing with a paired device failed: \(error.localizedDescription, privacy: .public)")
                await answer(.init(outcome: .failed, name: name), code: asking.code)
                step = .failed(PairingCloud.isOffline(error)
                    ? L("Could not reach iCloud. Check the connection and try again.")
                    : L("Could not share with that device. Try again in a moment."))
            }
        }
    }

    /// Cancelled while the device was being let in: it hears no, from a task
    /// of its own, as the cancelled one may not reach iCloud any more, and
    /// an account let in only now is taken off this Mac's zones again.
    private func withdraw(_ user: String, known: Bool, code: String) {
        Task {
            await answer(.init(outcome: .declined, name: name), code: code)
            if !known { await sync.removeAccess(user) }
        }
    }

    /// The person at the Mac says no; the code goes on showing.
    func decline() {
        guard case .asking = step, let asking else { return }
        self.asking = nil
        step = .showing
        Task { await answer(.init(outcome: .declined, name: name), code: asking.code) }
    }

    private func run() async {
        while !Task.isCancelled {
            now = Date()
            if schedule.advance(now: now) || offered[schedule.current.value] == nil {
                guard await offer(schedule.current) else { return }
            }
            await retire()
            if case .showing = step, Int(now.timeIntervalSince1970) % 2 == 0 { await look() }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    /// Puts the code's offer up, so a device that types it finds this Mac.
    private func offer(_ code: PairingCode) async -> Bool {
        guard let database, let name = PairingMessage.recordName(.offer, code: code.value),
              let payload = try? PairingMessage.seal(PairingMessage.Offer(name: self.name, platform: .mac), .offer,
                                                     code: code.value) else { return false }
        do {
            try await PairingCloud.save(PairingCloud.record(name, payload: payload), in: database)
            offered[code.value] = name
            return true
        } catch {
            log.error("A pairing code could not be put up: \(error.localizedDescription, privacy: .public)")
            step = .failed(PairingCloud.isOffline(error)
                ? L("Could not reach iCloud. Check the connection and try again.")
                : L("iCloud is not ready for connecting yet. Try again later."))
            return false
        }
    }

    /// Takes down the offers of codes that no longer count.
    private func retire() async {
        let live = Set(schedule.listening(at: now).map(\.value))
        let old = offered.filter { !live.contains($0.key) }
        guard !old.isEmpty, let database else { return }
        for code in old.keys { offered[code] = nil }
        await PairingCloud.remove(Array(old.values), from: database)
    }

    /// Whether a device typed one of the codes that count.
    private func look() async {
        guard let database else { return }
        var codes: [CKRecord.ID: String] = [:]
        for code in schedule.listening(at: now) {
            if let name = PairingMessage.recordName(.request, code: code.value), !seen.contains(name) {
                codes[CKRecord.ID(recordName: name)] = code.value
            }
        }
        guard !codes.isEmpty, let results = try? await database.records(for: Array(codes.keys), desiredKeys: nil) else { return }
        for (id, result) in results {
            guard let code = codes[id], case .success(let record) = result, let payload = PairingCloud.payload(record),
                  let request = PairingMessage.open(payload, as: PairingMessage.Request.self, .request, code: code)
            else { continue }
            seen.insert(id.recordName)
            guard case .showing = step else { return }
            asking = (request, code)
            step = .asking(request)
            return
        }
    }

    /// The answer, sealed with the code; taken down again after a while.
    private func answer(_ answer: PairingMessage.Answer, code: String) async {
        guard let database, let name = PairingMessage.recordName(.answer, code: code),
              let payload = try? PairingMessage.seal(answer, .answer, code: code) else { return }
        do {
            try await PairingCloud.save(PairingCloud.record(name, payload: payload), in: database)
        } catch {
            log.error("A pairing answer could not be sent: \(error.localizedDescription, privacy: .public)")
        }
        Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(PairingCloud.answerWait * 1_000_000_000))
            await PairingCloud.remove([name], from: database)
        }
    }
}

/// The side of the device that types the code.
@MainActor
final class PairingGuest: ObservableObject {
    enum Step: Equatable {
        case typing
        case looking
        /// Waiting for the person at the Mac, named here.
        case waiting(String)
        case joining(String)
        case joined(String)
        case sameAccount(String)
        case failed(String)
    }

    @Published private(set) var step = Step.typing

    private let sync: SyncCenter
    private var task: Task<Void, Never>?
    private static let attemptsKey = "pairingAttempts"

    init(sync: SyncCenter = .shared) {
        self.sync = sync
    }

    private var attempts: PairingAttempts {
        get {
            UserDefaults.standard.data(forKey: Self.attemptsKey)
                .flatMap { try? JSONDecoder().decode(PairingAttempts.self, from: $0) } ?? PairingAttempts()
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.attemptsKey) }
    }

    func join(_ typed: String, as device: SyncDevice) {
        guard let code = PairingCode.normalize(typed) else {
            step = .failed(L("Type the six digits the Mac shows."))
            return
        }
        guard attempts.mayTry() else {
            step = .failed(String(format: L("Too many wrong codes. Try again in %d seconds."), attempts.wait()))
            return
        }
        task?.cancel()
        task = Task { [weak self] in await self?.run(code, device) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        step = .typing
    }

    private func fail(_ message: String) {
        step = .failed(message)
    }

    private func run(_ code: String, _ device: SyncDevice) async {
        step = .looking
        guard let container = PairingCloud.container else { return fail(SyncProblem.notInThisBuild.text) }
        let database = container.publicCloudDatabase
        guard (try? await container.accountStatus()) == .available,
              let user = try? await container.userRecordID().recordName else {
            return fail(L("Sign in to iCloud to connect."))
        }
        guard let offerName = PairingMessage.recordName(.offer, code: code),
              let requestName = PairingMessage.recordName(.request, code: code),
              let answerName = PairingMessage.recordName(.answer, code: code) else { return }

        // The Mac showing this code.
        let offer: PairingMessage.Offer
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: offerName))
            guard let payload = PairingCloud.payload(record),
                  let found = PairingMessage.open(payload, as: PairingMessage.Offer.self, .offer, code: code) else {
                throw CKError(.unknownItem)
            }
            offer = found
        } catch {
            if PairingCloud.isOffline(error) { return fail(L("Could not reach iCloud. Check the connection and try again.")) }
            attempts.failed()
            return fail(L("That code is not right or has run out. Type the code the Mac shows now."))
        }
        attempts.succeeded()
        guard !Task.isCancelled else { return }
        step = .waiting(offer.name)

        // Asking to join, as this device and its account.
        var me = device
        me.account = user
        do {
            let payload = try PairingMessage.seal(PairingMessage.Request(user: user, device: me), .request, code: code)
            try await PairingCloud.save(PairingCloud.record(requestName, payload: payload), in: database)
        } catch {
            return fail(PairingCloud.isOffline(error)
                ? L("Could not reach iCloud. Check the connection and try again.")
                : L("That code was just used. Type the next one the Mac shows."))
        }

        // The answer from the person at the Mac.
        var answer: PairingMessage.Answer?
        let deadline = Date().addingTimeInterval(PairingCloud.answerWait)
        while answer == nil, Date() < deadline, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if let record = try? await database.record(for: CKRecord.ID(recordName: answerName)),
               let payload = PairingCloud.payload(record) {
                answer = PairingMessage.open(payload, as: PairingMessage.Answer.self, .answer, code: code)
            }
        }
        await PairingCloud.remove([requestName], from: database)
        guard !Task.isCancelled else { return }
        guard let answer else { return fail(L("The Mac did not answer. Try again with a new code.")) }

        switch answer.outcome {
        case .declined:
            fail(L("It was declined on the Mac."))
        case .failed:
            fail(L("The Mac could not share. Check that syncing is on there, then try again."))
        case .sameAccount:
            // The same Apple account: plain syncing does it.
            sync.setOn(true)
            step = .sameAccount(answer.name)
        case .joined:
            step = .joining(answer.name)
            do {
                var owner: String?
                for link in answer.shares {
                    let metadata = try await container.shareMetadata(for: link)
                    if metadata.participantStatus != .accepted { _ = try await container.accept(metadata) }
                    owner = owner ?? metadata.ownerIdentity.userRecordID?.recordName
                    let zoneOwner = metadata.share.recordID.zoneID.ownerName
                    if zoneOwner != CKCurrentUserDefaultName { owner = zoneOwner }
                }
                guard let owner else { throw CKError(.unknownItem) }
                sync.connect(owner: owner, name: answer.name)
                step = .joined(answer.name)
            } catch {
                log.error("Joining a Mac's shares failed: \(error.localizedDescription, privacy: .public)")
                fail(PairingCloud.isOffline(error)
                    ? L("Could not reach iCloud. Check the connection and try again.")
                    : L("Could not join the Mac. Try again with a new code."))
            }
        }
    }
}
#endif
