import Foundation

/// Which Snapfly this is: the one from GitHub, or the one from the Mac App
/// Store, built with APP_STORE (scripts/build-app.sh with STORE=1).
///
/// The App Store one runs in the sandbox. It may not change the screenshot
/// settings or read the Desktop on its own, so it watches Pictures › Snapfly
/// and shows where to point the Screenshot app; it remembers other folders
/// through bookmarks, and updates come from the App Store.
enum Edition {
    #if APP_STORE
    static let appStore = true
    #else
    static let appStore = false
    #endif

    /// The real home folder. In the sandbox the usual one is the app's
    /// container, which the Screenshot app cannot see.
    static let home: URL = {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()
}
