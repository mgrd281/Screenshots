import AppKit

MainActor.assumeIsolated {
    // Started by an AI app, like Claude, to answer it: no line, no menu.
    if MCPMode.isRequested { MCPMode.run() }
    // Opens the folders the App Store edition was let into, before the line
    // brings back the photos in them.
    _ = AppDelegate.extraFolders
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
