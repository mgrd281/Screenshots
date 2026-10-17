import AppKit
import CoreAudio

/// A call in progress: a meeting in Zoom or Teams, FaceTime, or a call on a
/// website in the browser. They all open the microphone, so the Mac's
/// input device says when one is on, whatever the app. While one lasts,
/// and Not during a call is on, the line comes down only when the shortcut
/// or the menu asks, the send button over chats stays away, and every
/// window of Snapfly's stays out of what other apps capture, like a shared
/// screen. Nothing is heard: the device is only asked whether it is in use.
@MainActor
final class Calls {
    static let shared = Calls()

    /// From Settings › Line, under Bring the line down. On unless turned off.
    static var keepsAway: Bool {
        get { !UserDefaults.standard.bool(forKey: "callsIgnored") }
        set {
            UserDefaults.standard.set(!newValue, forKey: "callsIgnored")
            shared.changed()
        }
    }

    /// The microphone is in use somewhere.
    private(set) var inCall = false

    /// Whether the line and the button keep away right now.
    var keepingAway: Bool { Self.keepsAway && inCall }

    /// Called when that changes.
    var onChange: () -> Void = {}

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var runningListener: AudioObjectPropertyListenerBlock?
    private var windowWatch: NSObjectProtocol?
    private var listening = false

    /// Watches the default input device, and whichever takes its place,
    /// like a headset put on.
    func start() {
        guard !listening else { return }
        listening = true
        var address = Self.defaultInputAddress
        _ = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        follow()
        // A window shown later, like a note or a floating photo, joins in.
        windowWatch = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let window = note.object as? NSWindow else { return }
                self.keepOffSharedScreens(window)
            }
        }
    }

    /// The default input device now, listened to for being in use.
    private func follow() {
        let now = Self.defaultInput()
        if now != device {
            var address = Self.runningAddress
            if device != AudioObjectID(kAudioObjectUnknown), let listener = runningListener {
                AudioObjectRemovePropertyListenerBlock(device, &address, .main, listener)
            }
            device = now
            runningListener = nil
            if now != AudioObjectID(kAudioObjectUnknown) {
                let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.check() }
                }
                runningListener = listener
                _ = AudioObjectAddPropertyListenerBlock(now, &address, .main, listener)
            }
        }
        check()
    }

    private func check() {
        let on = Self.isRunning(device)
        guard on != inCall else { return }
        inCall = on
        changed()
    }

    private func changed() {
        for window in NSApplication.shared.windows { keepOffSharedScreens(window) }
        onChange()
    }

    /// A window of Snapfly's own, a panel or one with a title bar, stays out
    /// of what other apps capture while a call lasts. Menus and the menu bar
    /// item are the system's, and stay as they are.
    func keepOffSharedScreens(_ window: NSWindow) {
        guard window is NSPanel || window.styleMask.contains(.titled) else { return }
        let wanted: NSWindow.SharingType = keepingAway ? .none : .readOnly
        if window.sharingType != wanted { window.sharingType = wanted }
    }

    // MARK: The device

    private static let defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    private static let runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    /// The Mac's default input device, or none.
    nonisolated static func defaultInput() -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = defaultInputAddress
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr
        else { return AudioObjectID(kAudioObjectUnknown) }
        return id
    }

    /// Whether any app is taking sound from the device.
    nonisolated static func isRunning(_ device: AudioObjectID) -> Bool {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return false }
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = runningAddress
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }
}
