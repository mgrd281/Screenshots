import AppKit
import AVFoundation

/// Smooth pointer, in Settings › General under Screen recordings, on until
/// turned off: screen recordings are made without the Mac's own pointer,
/// with where it went and the looks it had noted (`StudioCapture`), and
/// Snapfly draws its own: larger, gliding instead of jittering, pressed in
/// at each click (`StudioPointerStyle`). Studio draws it live on the
/// recording as it was made, as large as chosen there; and the recording on
/// the line gets the same pointer drawn in, in the background, so it can be
/// sent as it is, without Studio.
@MainActor
enum SmoothPointer {
    private static let key = "smoothPointer"

    static var isOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Called with a recording once its pointer is drawn in, to show it anew.
    static var onPointerAdded: (URL) -> Void = { _ in }

    /// Draws Snapfly's pointer into a recording just made, from the one kept
    /// for Studio, thirty frames a second, at its own size and with its sound
    /// as it was. Changed, moved or taken down meanwhile, it is left as it is.
    static func addPointer(to url: URL) {
        guard let clean = StudioStore.cleanSource(for: url), let events = StudioStore.events(for: url),
              events.drawsPointer else { return }
        let before = version(of: url)
        let target = url.deletingLastPathComponent()
            .appendingPathComponent(".pointer-\(UUID().uuidString)").appendingPathExtension(url.pathExtension)
        Task { @MainActor in
            let fm = FileManager.default
            do {
                let asset = AVURLAsset(url: clean)
                let duration = try await asset.load(.duration).seconds
                guard duration > 0, let track = try await asset.loadTracks(withMediaType: .video).first else { return }
                let natural = try await track.load(.naturalSize)
                // Nothing but the pointer: no zooms, no rings, no marks.
                var project = StudioProject()
                project.autoZoom = false
                project.showsClicks = false
                let look = StudioLook(project: project, events: events, duration: duration, pixels: natural,
                                      drawsPointer: true)
                try await StudioExport.run(clean, look: look, rate: 30, to: target, stop: StudioExport.Stop()) { _ in }
                guard fm.fileExists(atPath: url.path), version(of: url) == before else {
                    try? fm.removeItem(at: target)
                    return
                }
                _ = try fm.replaceItemAt(url, withItemAt: target)
                // As it was, so Studio, open on it meanwhile, still takes it
                // for the same recording.
                if let before { try? fm.setAttributes([.modificationDate: before], ofItemAtPath: url.path) }
                onPointerAdded(url)
            } catch {
                try? fm.removeItem(at: target)
                log.error("Could not draw the pointer into a recording: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func version(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
