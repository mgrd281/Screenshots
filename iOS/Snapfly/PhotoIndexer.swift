import BackgroundTasks
import Photos
import UIKit

/// Prepares photos ahead of time, with the owner's consent: reads the text
/// of each photo in the period, newest first, on this iPhone, and keeps it
/// (`IndexStore`), so covering one later starts at once. It works while
/// Snapfly is open, and in the background when iOS allows, while the iPhone
/// is charging; it never downloads from iCloud, and waits in Low Power Mode,
/// when the iPhone is hot or short of memory, and while a photo is being
/// covered. Nothing leaves the iPhone.
@MainActor
final class PhotoIndexer: NSObject, ObservableObject {
    static let shared = PhotoIndexer()
    /// The background task's name, as Info.plist allows it.
    static let taskID = "de.ghazarian.Snapfly.prepare"

    @Published private(set) var settings = IndexSettings.load()
    @Published private(set) var progress = IndexPlan.Progress()
    @Published private(set) var isRunning = false
    /// Why preparing waits, while it does.
    @Published private(set) var waiting: IndexPlan.Pause?
    @Published private(set) var lastUpdate: Date?
    /// How much room the prepared photos take.
    @Published private(set) var bytes = 0
    @Published private(set) var access = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    private var work: Task<Void, Never>?
    /// Each run started, so one stopped never clears the one after it.
    private var runs = 0
    /// Photos being covered now; preparing waits for them.
    private var held = 0
    private var shortOfMemory = false
    private var observing = false
    private var changes: Task<Void, Never>?

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil,
                                               queue: .main) { _ in
            MainActor.assumeIsolated { PhotoIndexer.shared.memoryIsShort() }
        }
        // Cooler, or out of Low Power Mode: what waited goes on, while Snapfly is open.
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { PhotoIndexer.shared.deviceChanged() }
            }
        }
    }

    private func deviceChanged() {
        guard settings.isOn, waiting != nil, pauseNow == nil,
              UIApplication.shared.applicationState == .active else { return }
        start()
    }

    var isLimited: Bool { access == .limited }

    // MARK: The owner's choices

    /// Turned on after the owner read what it does, for these photos.
    func turnOn(_ scope: IndexSettings.Scope) {
        settings.isOn = true
        settings.scope = scope
        settings.paused = false
        settings.save()
        observe()
        start()
    }

    /// Turned off: preparing stops and everything prepared is deleted.
    func turnOff() async {
        stop()
        settings = IndexSettings()
        settings.save()
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskID)
        await IndexStore.shared.deleteAll()
        await refresh()
    }

    func pause() {
        settings.paused = true
        settings.save()
        stop()
        waiting = .owner
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskID)
    }

    func resume() {
        settings.paused = false
        settings.save()
        waiting = nil
        start()
    }

    /// The owner would like it now, rather than later.
    func prepareNow() {
        resume()
    }

    /// Deletes everything prepared and waits, so nothing is prepared again
    /// until the owner goes on.
    func deleteIndex() async {
        pause()
        await IndexStore.shared.deleteAll()
        await refresh()
    }

    func choose(_ scope: IndexSettings.Scope) {
        guard scope != settings.scope else { return }
        settings.scope = scope
        settings.save()
        restart()
    }

    /// The photos picked, with Only selected photos.
    func pick(_ ids: [String]) {
        settings.selected = ids
        settings.save()
        restart()
    }

    // MARK: When it works

    /// The app is open again: Photos' access may have changed, and work may wait.
    func becameActive() {
        access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard settings.isOn else { return }
        observe()
        start()
    }

    /// The app went away: what is left is asked of iOS for later.
    func wentAway() {
        stop()
        schedule()
    }

    /// A photo is being covered: preparing waits, so it opens fast.
    func hold() {
        held += 1
    }

    func release() {
        held = max(0, held - 1)
        if held == 0, settings.isOn { start() }
    }

    /// Starts unless it runs already, or has nothing to do.
    @discardableResult
    func start() -> Task<Void, Never>? {
        if let work { return work }
        guard settings.isOn, access == .authorized || access == .limited else { return nil }
        runs += 1
        let mine = runs
        let task = Task { await run(mine) }
        work = task
        return task
    }

    private func stop() {
        work?.cancel()
        work = nil
    }

    private func restart() {
        stop()
        start()
    }

    private func memoryIsShort() {
        shortOfMemory = true
        Finder.forgetReadings()
        Task {
            try? await Task.sleep(for: .seconds(60))
            shortOfMemory = false
        }
    }

    private var pauseNow: IndexPlan.Pause? {
        let thermal = ProcessInfo.processInfo.thermalState
        return IndexPlan.pause(settings: settings, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                               hot: thermal == .serious || thermal == .critical, lowMemory: shortOfMemory,
                               busy: held > 0)
    }

    // MARK: Preparing

    /// Reads what is left, newest first, one photo at a time, until done,
    /// stopped, or the device needs it to wait.
    private func run(_ mine: Int) async {
        isRunning = true
        defer {
            if runs == mine {
                isRunning = false
                work = nil
            }
        }
        let store = IndexStore.shared
        let settings = settings
        let candidates = await Task.detached(priority: .utility) { Self.candidates(settings, now: Date()) }.value
        await store.forget(IndexPlan.stale(in: await store.list(), keeping: candidates))
        var list = await store.list()
        show(candidates, list)
        for candidate in IndexPlan.pending(candidates, in: list, now: Date()) {
            if Task.isCancelled { break }
            if let pause = pauseNow {
                waiting = pause
                break
            }
            // While the iPhone is locked, Photos and the files are closed.
            guard UIApplication.shared.isProtectedDataAvailable else { break }
            waiting = nil
            let photo = await Task.detached(priority: .utility) { await Self.read(candidate) }.value
            if Task.isCancelled { break }
            // Gone from Photos since: the next one.
            guard let photo else { continue }
            try? await store.keep(photo)
            list = await store.list()
            show(candidates, list)
        }
        if pauseNow == nil { waiting = nil }
    }

    /// The numbers, as the index holds them now.
    private func show(_ candidates: [IndexPlan.Candidate], _ list: IndexManifest) {
        progress = IndexPlan.progress(candidates, in: list)
        lastUpdate = list.lastUpdate
        bytes = list.bytes
    }

    /// The numbers, without preparing anything.
    func refresh() async {
        access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let settings = settings
        var candidates: [IndexPlan.Candidate] = []
        if settings.isOn {
            candidates = await Task.detached(priority: .utility) { Self.candidates(settings, now: Date()) }.value
        }
        show(candidates, await IndexStore.shared.list())
    }

    /// The photos in the period that may be prepared, as allowed.
    nonisolated static func candidates(_ settings: IndexSettings, now: Date) -> [IndexPlan.Candidate] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result: PHFetchResult<PHAsset>
        switch settings.scope {
        case .screenshots:
            guard let album = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots,
                                                                      options: nil).firstObject else { return [] }
            options.predicate = NSPredicate(format: "creationDate >= %@", settings.start(from: now) as NSDate)
            result = PHAsset.fetchAssets(in: album, options: options)
        case .allowed:
            options.predicate = NSPredicate(format: "creationDate >= %@ AND mediaType == %d",
                                            settings.start(from: now) as NSDate, PHAssetMediaType.image.rawValue)
            result = PHAsset.fetchAssets(with: options)
        case .selected:
            // The photos picked, whenever they were taken.
            guard !settings.selected.isEmpty else { return [] }
            result = PHAsset.fetchAssets(withLocalIdentifiers: settings.selected, options: options)
        }
        var found: [IndexPlan.Candidate] = []
        result.enumerateObjects { asset, _, _ in
            guard asset.mediaType == .image else { return }
            found.append(IndexPlan.Candidate(id: asset.localIdentifier, stamp: stamp(of: asset),
                                             created: asset.creationDate))
        }
        return found
    }

    nonisolated static func stamp(of asset: PHAsset) -> String {
        IndexedPhoto.stamp(width: asset.pixelWidth, height: asset.pixelHeight, modified: asset.modificationDate)
    }

    /// One photo read, as it is on the iPhone: never downloaded from
    /// iCloud. Nil when it is gone, or could not be had for now.
    nonisolated private static func read(_ candidate: IndexPlan.Candidate) async -> IndexedPhoto? {
        guard let asset = Library.asset(candidate.id) else { return nil }
        let (data, inCloud) = await localData(of: asset)
        guard let data, let image = Covering.upright(data) else {
            return IndexedPhoto(id: candidate.id, stamp: candidate.stamp, created: candidate.created,
                                width: asset.pixelWidth, height: asset.pixelHeight, status: inCloud ? .inCloud : .failed,
                                read: Date())
        }
        let lines = autoreleasepool { Finder.lines(in: image) }
        return IndexedPhoto(id: candidate.id, stamp: candidate.stamp, created: candidate.created,
                            width: asset.pixelWidth, height: asset.pixelHeight, lines: lines, read: Date())
    }

    nonisolated private static func localData(of asset: PHAsset) async -> (Data?, inCloud: Bool) {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = false
            options.version = .current
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                let inCloud = info?[PHImageResultIsInCloudKey] as? Bool ?? false
                continuation.resume(returning: (data, inCloud))
            }
        }
    }

    // MARK: Covering a photo prepared

    /// Gives the reading kept for a photo to the one about to be covered,
    /// when it is the photo as it is now, so it is not read again.
    nonisolated static func reuse(for id: String, image: CGImage) async -> Bool {
        guard IndexSettings.load().isOn, let asset = Library.asset(id),
              let photo = await IndexStore.shared.photo(id), photo.isCurrent(stamp: stamp(of: asset)) else { return false }
        Finder.remember(photo.textLines, for: image)
        return true
    }

    // MARK: In the background

    /// Tells iOS what to call when it lets preparing go on in the
    /// background; once, as the app starts.
    static func registerBackground() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: .main) { task in
            MainActor.assumeIsolated {
                guard let task = task as? BGProcessingTask else { return task.setTaskCompleted(success: false) }
                PhotoIndexer.shared.runInBackground(task)
            }
        }
    }

    private func runInBackground(_ task: BGProcessingTask) {
        access = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard let work = start() else { return task.setTaskCompleted(success: true) }
        task.expirationHandler = { work.cancel() }
        Task {
            await work.value
            task.setTaskCompleted(success: !work.isCancelled)
            schedule()
        }
    }

    /// Asks iOS to go on later, while the iPhone is charging, if anything is left.
    private func schedule() {
        guard settings.isOn, !settings.paused, progress.remaining > 0 else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskID)
            return
        }
        let request = BGProcessingTaskRequest(identifier: Self.taskID)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Photos' changes

    /// New photos are prepared while Snapfly is open.
    private func observe() {
        guard !observing, access == .authorized || access == .limited else { return }
        observing = true
        PHPhotoLibrary.shared().register(self)
    }
}

extension PhotoIndexer: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in self.libraryChanged() }
    }

    /// A moment after the last change, what is new is prepared.
    private func libraryChanged() {
        changes?.cancel()
        changes = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, settings.isOn, UIApplication.shared.applicationState == .active else { return }
            if work == nil { start() } else { await refresh() }
        }
    }
}
