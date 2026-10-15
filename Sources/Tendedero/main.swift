import AppKit

MainActor.assumeIsolated {
    // Opens the folders the App Store edition was let into, before the line
    // brings back the photos in them.
    _ = AppDelegate.extraFolders
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
