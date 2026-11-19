import AppKit

/// Connect to Claude, from Settings › AI Assistant: Snapfly is added to the
/// MCP servers Claude on this Mac starts, in Claude's own settings file,
/// beside any others there, so Claude can ask Snapfly (`MCPMode`). Claude
/// reads the file as it opens, so it is opened again afterwards. The App
/// Store edition may write there only once the owner chooses Claude's folder.
@MainActor
enum ClaudeConnect {
    static let bundleID = "com.anthropic.claudefordesktop"
    nonisolated static let serverName = "snapfly"
    private static let connectedKey = "connectedToClaude"

    static var folder: URL {
        Edition.home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
    }

    /// What Claude starts: this very Snapfly, to answer it.
    static var command: String {
        Bundle.main.executableURL?.path ?? "/Applications/Snapfly.app/Contents/MacOS/Snapfly"
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// Whether Snapfly was added to Claude, and still is where that can be read.
    static var isConnected: Bool {
        if !Edition.appStore, let data = try? Data(contentsOf: file(in: folder)) {
            return contains(data, command: command)
        }
        return UserDefaults.standard.bool(forKey: connectedKey)
    }

    enum Outcome {
        case connected, notInstalled, failed, cancelled
    }

    /// Adds Snapfly to Claude's settings: at once in the download edition,
    /// after the owner chooses Claude's folder in the App Store one.
    static func connect() -> Outcome {
        guard isInstalled else { return .notInstalled }
        guard Edition.appStore else { return write(into: folder) }
        let panel = NSOpenPanel()
        panel.directoryURL = folder
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = L("Choose the folder named Claude, so Snapfly can add itself to Claude’s settings.")
        panel.prompt = L("Connect")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let chosen = panel.url else { return .cancelled }
        guard chosen.lastPathComponent == "Claude" else { return .failed }
        return write(into: chosen)
    }

    private static func write(into folder: URL) -> Outcome {
        let file = file(in: folder)
        let existing = try? Data(contentsOf: file)
        // What is there and cannot be read is left as it is.
        guard let data = merged(existing, command: command) else { return .failed }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            log.error("Could not write Claude's settings: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
        UserDefaults.standard.set(true, forKey: connectedKey)
        MCPMode.isOn = true
        return .connected
    }

    private static func file(in folder: URL) -> URL {
        folder.appendingPathComponent("claude_desktop_config.json")
    }

    /// Claude's settings with Snapfly among its MCP servers, everything else
    /// kept as it was; nil when what is there is not settings Snapfly can
    /// read, which are then left alone.
    nonisolated static func merged(_ existing: Data?, command: String) -> Data? {
        var settings: [String: Any] = [:]
        if let existing, !existing.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            guard let read = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any] else { return nil }
            settings = read
        }
        var servers: [String: Any] = [:]
        if let there = settings["mcpServers"] {
            guard let there = there as? [String: Any] else { return nil }
            servers = there
        }
        servers[serverName] = ["command": command, "args": [MCPMode.argument]]
        settings["mcpServers"] = servers
        return try? JSONSerialization.data(withJSONObject: settings,
                                           options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Whether Claude's settings start this Snapfly to answer it.
    nonisolated static func contains(_ data: Data, command: String) -> Bool {
        guard let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let servers = settings["mcpServers"] as? [String: Any],
              let snapfly = servers[serverName] as? [String: Any] else { return false }
        return snapfly["command"] as? String == command && (snapfly["args"] as? [String] ?? []).contains(MCPMode.argument)
    }
}
