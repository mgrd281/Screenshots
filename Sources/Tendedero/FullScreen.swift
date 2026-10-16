import AppKit

#if !APP_STORE
// The window server knows the type of the Space each display is showing.
// These calls are private but stable for a decade, need no permission, and
// are what window managers like yabai rely on. A full screen Space is type 4.
// The App Store does not allow private calls, so its edition goes by the
// windows on screen instead.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> CFArray
#endif

enum FullScreen {
    private static let fullScreenSpaceType = 4

    /// Whether the line also comes down over full screen apps, so screenshots
    /// stay within reach while you work in one. Off unless turned on: a video
    /// or a presentation should not get a clothesline across the top.
    static var showLineOver: Bool {
        get { UserDefaults.standard.bool(forKey: "showOverFullScreen") }
        set { UserDefaults.standard.set(newValue, forKey: "showOverFullScreen") }
    }

    /// True when the line should keep away from the given screen.
    static func blocksLine(on screen: NSScreen) -> Bool {
        !showLineOver && isActive(on: screen)
    }

    /// True when the given screen is currently showing a full screen app,
    /// like a video or a presentation.
    static func isActive(on screen: NSScreen) -> Bool {
        #if APP_STORE
        return hasWindowFilling(screen)
        #else
        return spaceIsFullScreen(on: screen)
        #endif
    }

    #if !APP_STORE
    private static func spaceIsFullScreen(on screen: NSScreen) -> Bool {
        guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]],
              !displays.isEmpty else { return false }

        // With "Displays have separate Spaces" off there is a single entry
        // that covers every screen.
        let entry: [String: Any]?
        if displays.count == 1 {
            entry = displays.first
        } else {
            let uuid = uuidString(for: screen)
            entry = displays.first { ($0["Display Identifier"] as? String) == uuid }
        }
        let current = entry?["Current Space"] as? [String: Any]
        return (current?["type"] as? Int) == fullScreenSpaceType
    }
    #endif

    /// Whether another app's ordinary window covers the whole screen, as a
    /// full screen app does. Reading where windows are needs no permission.
    private static func hasWindowFilling(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return false }
        let display = CGDisplayBounds(number)
        let own = ProcessInfo.processInfo.processIdentifier
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != own,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return fills(rect, display: display, notch: screen.safeAreaInsets.top)
        }
    }

    /// A window that fills a display, top to bottom. On a screen with a
    /// camera notch, full screen apps start below it. Both are in the window
    /// server's points, counted from the top.
    static func fills(_ window: CGRect, display: CGRect, notch: CGFloat) -> Bool {
        let below = CGRect(x: display.minX, y: display.minY + notch, width: display.width, height: display.height - notch)
        return TimeStamp.isScreen(window, among: [display, below])
    }

    private static func uuidString(for screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
