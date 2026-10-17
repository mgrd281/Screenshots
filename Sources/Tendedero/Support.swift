import AppKit
import SwiftUI

/// Settings › Support: where to find help, a way to write about a problem
/// or an idea with the details that help already in the email, and those
/// details to copy. The credit the licence asks for ends the pane.
@MainActor
struct SupportPane: View {
    @ObservedObject var prefs: Preferences
    /// The details were just copied; the button says so for a moment.
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                SupportRow(symbol: "questionmark.circle.fill", title: L("Help & Support"),
                           detail: L("Guides and answers, and how to reach us.")) {
                    SettingsButton(L("Open")) { NSWorkspace.shared.open(AppDelegate.supportURL) }
                }
                SupportRow(symbol: "exclamationmark.bubble.fill", title: L("Report a Problem"),
                           detail: L("Opens an email with what we need to look into it.")) {
                    SettingsButton(L("Write…")) { write(L("Report a Problem")) }
                }
                SupportRow(symbol: "lightbulb.fill", title: L("Suggest a Feature"),
                           detail: L("Tell us what would help you.")) {
                    SettingsButton(L("Write…")) { write(L("Suggest a Feature")) }
                }
            }
            Section {
                SupportRow(symbol: "stethoscope", title: L("Diagnostic details"),
                           detail: L("Version, macOS and permissions. Nothing personal.")) {
                    SettingsButton(copied ? L("Copied") : L("Copy")) { copy() }
                        .disabled(copied)
                }
            } footer: {
                // The MIT License asks for the original's credit to stay.
                Text(L("Based on Tendedero by Alejandro Buján, under the MIT License."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// An email to the support address, the subject and the details filled
    /// in, for the owner to add what happened.
    private func write(_ subject: String) {
        guard let url = Support.mail(to: Support.address, subject: "Snapfly: \(subject)",
                                     body: "\n\n\n" + diagnostics) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    /// What helps with a request: the version, macOS and the Mac, the
    /// language, and where the permissions stand.
    private var diagnostics: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return Support.details(version: info["CFBundleShortVersionString"] as? String ?? "",
                               build: info["CFBundleVersion"] as? String ?? "",
                               appStore: Edition.appStore,
                               system: "macOS " + ProcessInfo.processInfo.operatingSystemVersionString,
                               model: Support.model,
                               language: Locale.current.identifier,
                               permissions: [(L("Screen Recording"), Self.word(for: Permissions.screen)),
                                             (L("Accessibility"), Self.word(for: Permissions.keys))])
    }

    /// A permission's state, in the words the Permissions pane uses.
    private static func word(for status: Permissions.Status) -> String {
        switch status {
        case .allowed: L("Allowed")
        case .denied: L("Not allowed yet")
        case .notAsked: L("Not asked yet")
        case .notRunning: L("Not open")
        }
    }
}

/// One thing to do: its symbol on an ink tile, its name with a line on what
/// it does, and its button on the trailing edge.
private struct SupportRow<Action: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(InkTile.glyph)
                .frame(width: 28, height: 28)
                .background(InkTile.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            action()
        }
        .padding(.vertical, 2)
    }
}

/// Writing for help: the address, the mail link, and the details that go
/// with it.
enum Support {
    /// The support address, the one the website's support page gives.
    static let address = "mgrdegh@gmx.de"

    /// A mail link with the subject and body filled in.
    static func mail(to address: String, subject: String, body: String) -> URL? {
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = address
        parts.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        return parts.url
    }

    /// The details, one a line: the app and its build (and that it is the
    /// App Store's), the system and the Mac, the language, then each
    /// permission and where it stands.
    static func details(version: String, build: String, appStore: Bool, system: String, model: String,
                        language: String, permissions: [(String, String)]) -> String {
        var lines = ["Snapfly \(version) (\(build))" + (appStore ? " · App Store" : ""), "\(system) · \(model)", language]
        lines += permissions.map { "\($0.0): \($0.1)" }
        return lines.joined(separator: "\n")
    }

    /// The Mac, as it names itself, and its kind of processor.
    static var model: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var chars = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &chars, &size, nil, 0)
        let name = String(cString: chars)
        #if arch(arm64)
        return name.isEmpty ? "Apple silicon" : "\(name) · Apple silicon"
        #else
        return name.isEmpty ? "Intel" : "\(name) · Intel"
        #endif
    }
}
