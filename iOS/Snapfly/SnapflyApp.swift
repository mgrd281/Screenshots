import SwiftUI

/// Snapfly on the iPhone: screenshots with their private details covered,
/// ready to send. iOS lets no app watch the screen or float over the others,
/// so it works from the screenshots in Photos, and from Shortcuts, which a
/// double tap on the back of the iPhone can run. The covering is the Mac's
/// own (`Shared/PrivateText.swift`), and like there it happens on the device.
@main
struct SnapflyApp: App {
    init() {
        // How soon the first run shows is measured from here.
        _ = FirstRunCoordinator.launched
        // Whoever used Snapfly before Pro begins keeps every feature.
        Plan.recordFirstLaunch()
        // Preparing photos ahead of time goes on in the background only if
        // the owner turned it on; iOS needs to know what to call, at launch.
        PhotoIndexer.registerBackground()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
