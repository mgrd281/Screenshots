import CryptoKit
import Foundation

/// Copy Link: a photo as it leaves the line, a recording or a PDF, uploaded
/// to Snapfly's share links on the owner's Cloudflare account (`share/`),
/// behind a link that works for seven days. These are its rules without a
/// screen: what may go, the requests, reading the answers, and the links
/// kept, each with the token that deletes it.
enum ShareLinks {
    /// One link made, kept until it runs out.
    struct Link: Codable, Equatable {
        var id: String
        var url: URL
        var deleteToken: String
        var expires: Date
        /// The file on the line it was made from.
        var source: String
        /// Which version of what left: a photo covered again is a new link.
        var fingerprint: String
    }

    enum Failure: Error, Equatable {
        case notSetUp, kind, tooLarge, busy, offline, failed

        var message: String {
            switch self {
            case .notSetUp, .failed: L("Could not make the link. Try again later.")
            case .kind: L("This kind of file cannot be shared as a link.")
            case .tooLarge: L("This file is too large for a link. Links take files up to 95 MB.")
            case .busy: L("Too many links in a short time. Try again in a minute.")
            case .offline: L("Could not reach the link service. Check the connection and try again.")
            }
        }
    }

    /// The largest file taken, as the Worker takes it.
    static let maxBytes = 95 * 1024 * 1024

    /// Where links are made, from Info.plist; none until the owner's
    /// Cloudflare account has them, and then Copy Link stays out of menus.
    static var service: URL? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: "SnapflyShareURL") as? String,
              let url = URL(string: text), url.scheme == "https" else { return nil }
        return url
    }

    /// The type a file goes as, by its ending; nil for what may not go.
    static func contentType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "heic": "image/heic"
        case "mp4", "m4v": "video/mp4"
        case "mov": "video/quicktime"
        case "pdf": "application/pdf"
        default: nil
        }
    }

    static func uploadRequest(for file: URL, to service: URL) throws -> URLRequest {
        guard let type = contentType(for: file) else { throw Failure.kind }
        var request = URLRequest(url: service.appendingPathComponent("api/files"), timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue(type, forHTTPHeaderField: "Content-Type")
        return request
    }

    static func deleteRequest(for link: Link, to service: URL) -> URLRequest {
        var request = URLRequest(url: service.appendingPathComponent("api/files/\(link.id)"), timeoutInterval: 30)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(link.deleteToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// The link the service made, or what went wrong.
    static func link(status: Int, data: Data, source: String, fingerprint: String) throws -> Link {
        switch status {
        case 201, 200: break
        case 413: throw Failure.tooLarge
        case 415: throw Failure.kind
        case 429: throw Failure.busy
        default: throw Failure.failed
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String, let text = json["url"] as? String, let url = URL(string: text),
              let token = json["deleteToken"] as? String, let due = json["expires"] as? String,
              let expires = ISO8601DateFormatter.withFractions.date(from: due) ?? ISO8601DateFormatter().date(from: due)
        else { throw Failure.failed }
        return Link(id: id, url: url, deleteToken: token, expires: expires, source: source, fingerprint: fingerprint)
    }

    /// Days a link still works, counting a part of a day as a day.
    static func daysLeft(_ link: Link, now: Date = Date()) -> Int {
        max(1, Int((link.expires.timeIntervalSince(now) / 86_400).rounded(.up)))
    }

    /// What tells one version of a file from another: what is in it, as
    /// the copy that leaves the line is written afresh each time.
    static func fingerprint(of file: URL) -> String? {
        guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: The links kept

    private static let key = "shareLinks"

    /// The links still working, newest last.
    static func kept(in defaults: UserDefaults = .standard, now: Date = Date()) -> [Link] {
        guard let data = defaults.data(forKey: key),
              let links = try? JSONDecoder().decode([Link].self, from: data) else { return [] }
        return links.filter { $0.expires > now }
    }

    static func keep(_ links: [Link], in defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(links), forKey: key)
    }

    static func add(_ link: Link, in defaults: UserDefaults = .standard, now: Date = Date()) {
        keep(kept(in: defaults, now: now) + [link], in: defaults)
    }

    static func remove(_ link: Link, in defaults: UserDefaults = .standard) {
        keep(kept(in: defaults).filter { $0.id != link.id }, in: defaults)
    }

    /// A working link to this very version of the file, made before, to copy again.
    static func reusable(source: String, fingerprint: String, in defaults: UserDefaults = .standard,
                        now: Date = Date()) -> Link? {
        // A link with less than a day left is made afresh, so it does not run out once sent.
        kept(in: defaults, now: now).last {
            $0.source == source && $0.fingerprint == fingerprint && $0.expires.timeIntervalSince(now) > 86_400
        }
    }

    /// The working links made from a file, whatever its version.
    static func links(for source: String, in defaults: UserDefaults = .standard, now: Date = Date()) -> [Link] {
        kept(in: defaults, now: now).filter { $0.source == source }
    }
}

private extension ISO8601DateFormatter {
    /// "2026-10-26T09:41:00.123Z", as JavaScript writes a date.
    static let withFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
