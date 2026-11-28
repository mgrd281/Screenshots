import AppKit
import AVFoundation

/// Smooth pointer, in Settings › General under Screen recordings, on until
/// turned off: screen recordings are made without the Mac's own pointer,
/// with where it went and the looks it had noted (`StudioCapture`), and
/// Snapfly draws its own: larger, gliding instead of jittering, pressed in
/// at each click (`StudioPointerStyle`). Studio draws it live on the
/// recording as it was made, as large and in the shape chosen there; and the
/// recording on the line gets the pointer as last set drawn in, in the
/// background, so it can be sent as it is, without Studio. The same pass
/// draws the time stamp's band above it (`VideoStamp`).
@MainActor
enum SmoothPointer {
    private static let key = "smoothPointer"

    static var isOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Called with a recording once its pointer or its time stamp is drawn
    /// in, to show it anew.
    static var onPointerAdded: (URL) -> Void = { _ in }

    /// Draws Snapfly's pointer into a recording just made, from the one kept
    /// for Studio, thirty frames a second, at its own size and with its sound
    /// as it was. With the time stamp on as it was made, the band goes above
    /// its picture in the same pass, so it is made again only once; without
    /// Snapfly's pointer, the band alone. Changed, moved or taken down
    /// meanwhile, it is left as it is.
    static func addPointer(to url: URL) {
        // As last set in Studio; hidden there, the recording stays without one.
        let style = StudioModel.lastPointer
        let clean = StudioStore.cleanSource(for: url)
        let events = StudioStore.events(for: url)
        let pointer = style.shows && clean != nil && events?.drawsPointer == true
        // A band is drawn only onto the recording as it was made, never a
        // second time over one already drawn in.
        let stamp = clean == nil && VideoStamp.isDrawnIn(url) ? nil : VideoStamp.stamp(for: url)
        guard pointer || stamp != nil else { return }
        // The recording as it was made, which Studio keeps; the one on the
        // line, should none be kept.
        let source = clean ?? url
        let before = version(of: url)
        let target = url.deletingLastPathComponent()
            .appendingPathComponent(".pointer-\(UUID().uuidString)").appendingPathExtension(url.pathExtension)
        Task { @MainActor in
            let fm = FileManager.default
            do {
                let asset = AVURLAsset(url: source)
                let duration = try await asset.load(.duration).seconds
                guard duration > 0, let track = try await asset.loadTracks(withMediaType: .video).first else {
                    throw StudioExport.Failure.noPicture
                }
                let natural = try await track.load(.naturalSize)
                // Nothing but the pointer and the band: no zooms, no rings, no marks.
                var project = StudioProject()
                project.autoZoom = false
                project.showsClicks = false
                project.pointer = style
                let look = StudioLook(project: project, events: events, duration: duration, pixels: natural,
                                      drawsPointer: pointer)
                try await StudioExport.run(source, look: look, rate: 30, stamp: stamp, to: target,
                                           stop: StudioExport.Stop()) { _ in }
                guard fm.fileExists(atPath: url.path), version(of: url) == before else {
                    try? fm.removeItem(at: target)
                    return
                }
                _ = try fm.replaceItemAt(url, withItemAt: target)
                // As it was, so Studio, open on it meanwhile, still takes it
                // for the same recording.
                if let before { try? fm.setAttributes([.modificationDate: before], ofItemAtPath: url.path) }
                if let stamp { VideoStamp.drawnIn(stamp, into: url) }
                onPointerAdded(url)
            } catch {
                try? fm.removeItem(at: target)
                log.error("Could not draw the pointer or the time stamp into a recording: \(error.localizedDescription, privacy: .public)")
                // The band was to be there, as it is on every screenshot.
                if stamp != nil { Notice.show(L("Could not add the time stamp to the recording.")) }
            }
        }
    }

    private static func version(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
