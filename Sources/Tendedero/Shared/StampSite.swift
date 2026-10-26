import Foundation

/// The website the time stamp names: its host alone, like
/// "mail.google.com", never the rest of the page's address, whose path,
/// search and fragment can hold an email address, a customer's search or a
/// link that signs someone in. The stamp is drawn after the covering, into
/// every copy that leaves the line, so nothing it says is ever covered.
enum StampSite {
    /// The host of a web page's address, in lower case; nil for anything
    /// but a website, like a file open in the browser, and for what cannot
    /// be read as an address. A host alone, as a stamp keeps it, gives
    /// itself back, and a stamp kept from before, with the whole address,
    /// gives no more than its host.
    static func host(of page: String) -> String? {
        let page = page.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = URL(string: page)?.scheme == nil ? "https://" + page : page
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", var host = url.host?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? nil : host
    }
}
