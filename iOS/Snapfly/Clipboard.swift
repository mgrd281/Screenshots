import UIKit
import UniformTypeIdentifiers

/// The clipboard, for what Snapfly copies. A copy without covers holds
/// every private detail: it stays on this iPhone, never passed to a Mac or
/// iPad nearby (Universal Clipboard), and is gone after ten minutes. A
/// covered copy stays as any copy does.
enum Clipboard {
    static func put(_ items: [[String: Any]], covered: Bool) {
        let options: [UIPasteboard.OptionsKey: Any] = covered
            ? [:] : [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(600)]
        UIPasteboard.general.setItems(items, options: options)
    }

    static func put(_ text: String, covered: Bool) {
        put([[UTType.utf8PlainText.identifier: text]], covered: covered)
    }

    static func put(_ data: Data, as type: UTType, covered: Bool) {
        put([[type.identifier: data]], covered: covered)
    }
}
