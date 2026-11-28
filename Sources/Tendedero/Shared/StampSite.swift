import Foundation

/// The page the time stamp names. Since November 2026, at the owner's
/// choice, a stamp shows the page's whole address, as evidence needs it:
/// which review, which listing, which order. Only a user name and a
/// password written into an address are left out. The stamp is drawn after
/// the covering, into every copy that leaves the line, so nothing it says is
/// ever covered.
enum StampSite {
    /// The page's whole address, with its scheme and host in lower case and
    /// without a user name or password; nil for anything but a website, like
    /// a file open in the browser, and for what cannot be read as an address.
    /// A host alone, as a stamp from before kept it, gives itself back as an
    /// address.
    static func address(of page: String) -> String? {
        let page = page.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = URL(string: page)?.scheme == nil ? "https://" + page : page
        guard var parts = URLComponents(string: text), let scheme = parts.scheme?.lowercased(),
              scheme == "http" || scheme == "https", var host = parts.host?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty else { return nil }
        parts.scheme = scheme
        parts.host = host
        parts.user = nil
        parts.password = nil
        return parts.string
    }

    /// The host of a web page's address, in lower case; nil for anything
    /// but a website. A host alone gives itself back.
    static func host(of page: String) -> String? {
        address(of: page).flatMap { URLComponents(string: $0)?.host }
    }
}
