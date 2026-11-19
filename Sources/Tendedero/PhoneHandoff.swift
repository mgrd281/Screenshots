import AppKit

/// The newest photo on the line, offered to the iPhone nearby with Handoff
/// (`PhotoHandoff`). Each photo that hangs is offered as it hangs; Open on
/// iPhone in a photo's menu offers that one and brings Snapfly to the front
/// while it waits, since a Mac may offer only what the app in front does.
/// When the iPhone asks, the photo goes as it leaves the line, covered as
/// Settings says, and the app that was in front comes back.
@MainActor
final class PhoneHandoff: NSObject, NSUserActivityDelegate {
    static let shared = PhoneHandoff()

    private var activity: NSUserActivity?
    /// The photo offered, on the line.
    private var offered: URL?
    /// The app in front before Open on iPhone brought Snapfly forward.
    private var before: NSRunningApplication?
    /// The note saying where to look on the iPhone.
    private var note: UUID?

    /// Offers a photo that just hung. Recordings and PDFs are left out.
    func offer(_ url: URL) {
        guard Self.isPicture(url) else { return }
        activity?.invalidate()
        let activity = NSUserActivity(activityType: PhotoHandoff.activityType)
        activity.isEligibleForHandoff = true
        activity.supportsContinuationStreams = true
        activity.userInfo = [PhotoHandoff.nameKey: url.lastPathComponent]
        activity.delegate = self
        self.activity = activity
        offered = url
        activity.becomeCurrent()
    }

    /// Open on iPhone: this photo, with Snapfly in front until the iPhone
    /// takes it, and a note saying where to tap there.
    func openOnPhone(_ url: URL) {
        offer(url)
        guard offered == url else { return }
        if !NSApp.isActive {
            before = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
        }
        activity?.becomeCurrent()
        if let note { Notice.end(note) }
        note = Notice.show(L("On your iPhone, open the app switcher and tap Snapfly at the bottom."), lasting: 60) {
            PhoneHandoff.shared.giveBackFront()
        }
        // Not taken in a minute: the app that was in front comes back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            MainActor.assumeIsolated { PhoneHandoff.shared.giveBackFront() }
        }
    }

    /// The app that was in front before Open on iPhone, in front again,
    /// unless another was brought forward meanwhile.
    private func giveBackFront() {
        guard let before else { return }
        self.before = nil
        if NSApp.isActive { _ = before.activate(options: []) }
    }

    // MARK: The iPhone asks

    nonisolated func userActivity(_ userActivity: NSUserActivity?, didReceive inputStream: InputStream,
                                  outputStream: OutputStream) {
        DispatchQueue.main.async {
            Task { @MainActor in
                await PhoneHandoff.shared.send(to: outputStream, closing: inputStream)
            }
        }
    }

    /// The photo as it leaves the line, once its private details are
    /// covered, then written to the iPhone away from the main thread.
    private func send(to output: OutputStream, closing input: InputStream) async {
        guard let url = offered, FileManager.default.fileExists(atPath: url.path) else {
            output.open()
            output.close()
            return
        }
        // Still being covered: a little longer, never the original instead.
        for _ in 0..<40 where PrivateDetails.stillCovering(url, PrivateDetails.details) {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard !PrivateDetails.stillCovering(url, PrivateDetails.details) else {
            output.open()
            output.close()
            Notice.show(L("Still covering the private details…"))
            return
        }
        let file = PrivateDetails.shareable(url)
        let sent = await Task.detached(priority: .userInitiated) { () -> Bool in
            input.open()
            defer { input.close() }
            guard let data = try? Data(contentsOf: file) else {
                output.open()
                output.close()
                return false
            }
            return PhotoHandoff.send(data, to: output)
        }.value
        if let note { Notice.end(note) }
        note = nil
        giveBackFront()
        if sent {
            Guide.shared.happened(.photoUsed)
            Notice.show(L("Sent to your iPhone."), done: true)
        } else {
            log.error("A photo could not be handed to the iPhone")
            Notice.show(L("The photo could not be sent to your iPhone."))
        }
    }

    /// Pictures only: what the iPhone opens to cover and send.
    private static func isPicture(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "heic", "tiff", "tif", "gif", "webp"].contains(url.pathExtension.lowercased())
    }
}
