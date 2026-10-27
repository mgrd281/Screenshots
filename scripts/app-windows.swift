// Lists the windows an app shows on screen, one per line: its level, its
// frame and how opaque it is, for scripts/launch-check.sh. With "menubar"
// instead of a pid, every window at the menu bar's levels, with its owner.
// Usage: swift scripts/app-windows.swift <pid>|menubar
import CoreGraphics
import Foundation

let argument = CommandLine.arguments.dropFirst().first ?? ""
let pid = Int(argument)
guard pid != nil || argument == "menubar" else {
    FileHandle.standardError.write("Usage: app-windows.swift <pid>|menubar\n".data(using: .utf8)!)
    exit(2)
}
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    let owner = window[kCGWindowOwnerPID as String] as? Int
    let level = window[kCGWindowLayer as String] as? Int ?? 0
    if let pid, owner != pid { continue }
    if pid == nil, !(20...30).contains(level) { continue }
    let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
    let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let frame = ["X", "Y", "Width", "Height"].map { Int(bounds[$0] ?? 0) }
    var line = "level \(level) frame \(frame[0]) \(frame[1]) \(frame[2]) \(frame[3]) alpha \(alpha)"
    if pid == nil { line += " owner \(window[kCGWindowOwnerName as String] as? String ?? "?")" }
    print(line)
}
