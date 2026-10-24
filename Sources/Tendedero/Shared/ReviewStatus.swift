import Foundation

/// How a page stands, in the one line under the Review title: what is
/// covered, what is still to check, what the owner's categories leave
/// visible, and what is wrong with the picture itself, a blurred part or
/// text read less well after cleaning. It never says nothing private was
/// found while anything is still to check, left visible or wrong. Pure, so
/// it is checked without a screen.
struct ReviewStatus: Equatable {
    /// Places covered and decided.
    var covered: Int
    /// Places still to check: covered or only offered, not yet decided.
    var open: Int
    /// What is wrong with the picture, each once.
    var hints: Int
    /// Private details found that the categories chosen leave visible, as
    /// names where Names is off.
    var visible = 0

    enum State: Equatable {
        /// Places are still to check.
        case open
        /// Private details are left visible, as the categories say.
        case visible
        /// Places are covered, and none is left to check or visible.
        case checked
        /// Nothing private, but something is wrong with the picture.
        case hinted
        /// Nothing covered, nothing to check, nothing visible, nothing wrong.
        case nothing
    }

    var state: State {
        if open > 0 { return .open }
        if visible > 0 { return .visible }
        if covered > 0 { return .checked }
        return hints > 0 ? .hinted : .nothing
    }

    /// "3 verdeckt" and what is still open, or "Nichts Privates gefunden"
    /// only when nothing at all is.
    var covering: String? {
        switch state {
        case .open, .checked:
            guard covered > 0 else { return nil }
            if state == .checked, hints == 0 { return String(format: L("%d covered, everything checked"), covered) }
            return String(format: L("%d covered"), covered)
        case .visible: return covered > 0 ? String(format: L("%d covered"), covered) : L("Nothing covered")
        case .hinted: return L("Nothing private")
        case .nothing: return L("Nothing private found")
        }
    }

    /// What is still open after it, shown apart: "2 zu prüfen", "6
    /// sichtbar" where the categories leave details visible, or "1
    /// Qualitätshinweis" where nothing is to check but the picture has a
    /// fault.
    var pending: String? {
        if open > 0 { return String(format: L("%d to check"), open) }
        if visible > 0 { return String(format: L("%d visible"), visible) }
        guard hints > 0, state != .nothing else { return nil }
        return hints == 1 ? L("1 quality hint") : String(format: L("%d quality hints"), hints)
    }

    /// The whole line, as it reads: "3 verdeckt · 4 zu prüfen".
    var text: String {
        [covering, pending].compactMap { $0 }.joined(separator: " · ")
    }

    /// The same for VoiceOver, with what a tap does.
    var spoken: String {
        let said = [covering, pending].compactMap { $0 }.joined(separator: ", ")
        return state == .nothing ? said : said + ". " + L("Open the list.")
    }
}
