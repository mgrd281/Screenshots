import AppKit

/// Copy Link and Delete Link, in a photo's menu: the photo as it leaves the
/// line, covered, or a recording or a PDF, uploaded to Snapfly's share links
/// and its link copied, to paste anywhere. A link works for seven days; the
/// same version of a photo keeps its link, and Delete Link takes it down
/// before then. Only there when the build knows where links are made.
@MainActor
enum LinkSharing {
    static var isAvailable: Bool { ShareLinks.service != nil }

    /// Files being uploaded, so a second click waits for the first.
    private static var making: Set<String> = []

    /// The link copied, made first if this version of the file has none.
    /// - Parameters:
    ///   - file: what goes, the copy that leaves the line.
    ///   - source: the file on the line, which the link is kept under.
    static func copyLink(to file: URL, from source: URL) {
        guard let service = ShareLinks.service else { return }
        guard ShareLinks.contentType(for: file) != nil else {
            Notice.show(ShareLinks.Failure.kind.message)
            return
        }
        let key = source.path
        guard !making.contains(key) else { return }
        making.insert(key)
        let note = Notice.show(L("Making the link…"), working: true)
        Task { @MainActor in
            defer { making.remove(key) }
            let fingerprint = await Task.detached { ShareLinks.fingerprint(of: file) }.value ?? UUID().uuidString
            if let link = ShareLinks.reusable(source: key, fingerprint: fingerprint) {
                Notice.end(note)
                copied(link)
                return
            }
            do {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size <= ShareLinks.maxBytes else { throw ShareLinks.Failure.tooLarge }
                let request = try ShareLinks.uploadRequest(for: file, to: service)
                let (data, response) = try await URLSession.shared.upload(for: request, fromFile: file)
                let link = try ShareLinks.link(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data,
                                               source: key, fingerprint: fingerprint)
                ShareLinks.add(link)
                Notice.end(note)
                copied(link)
            } catch let failure as ShareLinks.Failure {
                Notice.end(note)
                Notice.show(failure.message)
            } catch let failure as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                                                     .dnsLookupFailed, .timedOut].contains(failure.code) {
                Notice.end(note)
                Notice.show(ShareLinks.Failure.offline.message)
            } catch {
                log.error("Could not make a share link: \(error.localizedDescription, privacy: .public)")
                Notice.end(note)
                Notice.show(ShareLinks.Failure.failed.message)
            }
        }
    }

    private static func copied(_ link: ShareLinks.Link) {
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(link.url.absoluteString, forType: .string)
        Notice.show(String(format: L("Link copied. It works for %d more days. Click to open it."),
                           ShareLinks.daysLeft(link)), done: true, lasting: 6) {
            NSWorkspace.shared.open(link.url)
        }
    }

    static func hasLink(_ source: URL) -> Bool {
        !ShareLinks.links(for: source.path).isEmpty
    }

    /// Every link made from the file, taken down now.
    static func deleteLinks(_ source: URL) {
        guard let service = ShareLinks.service else { return }
        let links = ShareLinks.links(for: source.path)
        guard !links.isEmpty else { return }
        Task { @MainActor in
            var failed = false
            for link in links {
                do {
                    let (_, response) = try await URLSession.shared.data(for: ShareLinks.deleteRequest(for: link, to: service))
                    // Gone already counts as gone.
                    if [200, 404].contains((response as? HTTPURLResponse)?.statusCode ?? 0) {
                        ShareLinks.remove(link)
                    } else {
                        failed = true
                    }
                } catch {
                    failed = true
                }
            }
            if failed {
                Notice.show(L("Could not delete the link. Try again later."))
            } else {
                Notice.show(L("Link deleted. It no longer opens."), done: true)
            }
        }
    }
}
