// Lists the windows an app shows on screen, one per line: its level, its
// frame and how opaque it is, for scripts/launch-check.sh.
// Usage: swift scripts/app-windows.swift <pid>
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int(CommandLine.arguments[1]) else {
    FileHandle.standardError.write("Usage: app-windows.swift <pid>\n".data(using: .utf8)!)
    exit(2)
}
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerPID as String] as? Int) == pid {
    let level = window[kCGWindowLayer as String] as? Int ?? 0
    let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let frame = ["X", "Y", "Width", "Height"].map { Int(bounds[$0] ?? 0) }
    print("level \(level) frame \(frame[0]) \(frame[1]) \(frame[2]) \(frame[3]) alpha \(alpha)")
}
