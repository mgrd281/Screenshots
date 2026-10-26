import AppKit
import SwiftUI

/// Settings › Workspace: whether screenshots are kept in a folder of their
/// own, where it is and what it is called, what is in it, and the categories
/// it is divided into. Every control here does what it says: nothing is
/// there for show, and nothing deletes a file but the one button that says
/// so and asks first.
struct WorkspacePane: View {
    @ObservedObject var workspace: Workspace
    @State private var folderName = ""
    /// The folder's name last tried, so leaving the field after Return, or
    /// after a name refused, does not try it again.
    @State private var triedName = ""
    @FocusState private var folderFocused: Bool
    @State private var newCategory = ""

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { workspace.isOn },
                                     set: { $0 ? workspace.enable() : workspace.disable() })) {
                    Text(L("Keep screenshots in a workspace folder"))
                    Text(L("A folder of its own on your Desktop, with a folder for each kind of screenshot"))
                }
                if let problem = workspace.problem {
                    problemRow(problem)
                }
            } header: {
                Text(L("Workspace"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Off, nothing changes: screenshots stay in Snapfly’s own folder, out of sight. Turning it off later never deletes a screenshot."))
                    Text(L("If iCloud Drive keeps your Desktop, everything in this folder goes to iCloud, private details covered or not. Snapfly covers them only in what leaves the line."))
                }
                .foregroundStyle(.secondary)
            }
            if workspace.isOn {
                location
                categories
                danger
            }
        }
        .formStyle(.grouped)
        .onAppear {
            folderName = workspace.config.name
            workspace.refreshStats()
        }
        .onChange(of: workspace.config.name) { _, name in folderName = name }
        // A name typed and left, as the pane closes, is kept too.
        .onDisappear { renameFolder(onReturn: false) }
    }

    /// The folder's name as typed: on Return, and once the field is left,
    /// unless that name was tried already. An empty name or the same one
    /// changes nothing, and the field shows the name again.
    private func renameFolder(onReturn: Bool) {
        guard let name = WorkspaceNames.clean(folderName), name != workspace.config.name else {
            folderName = workspace.config.name
            return
        }
        guard onReturn || folderName != triedName else { return }
        triedName = folderName
        workspace.rename(to: folderName)
    }

    // MARK: Pieces

    private func problemRow(_ problem: Workspace.Problem) -> some View {
        LabeledContent {
            HStack {
                if problem == .noAccess {
                    SettingsButton(L("Open Settings…")) { Permissions.open("Privacy_FilesAndFolders") }
                }
                SettingsButton(L("Try Again")) { workspace.retry() }
            }
        } label: {
            Label {
                Text(problem.message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text(L("Until then, screenshots are kept in Snapfly’s own folder."))
        }
    }

    private var location: some View {
        Section {
            LabeledContent {
                HStack {
                    SettingsButton(L("Show in Finder")) { workspace.reveal() }
                    SettingsButton(L("Change Location…")) { workspace.chooseLocation() }
                        .disabled(workspace.busy)
                }
            } label: {
                Text(L("Folder"))
                Text(Folders.placeName(workspace.root))
            }
            TextField(L("Folder name"), text: $folderName)
                .focused($folderFocused)
                .onSubmit { renameFolder(onReturn: true) }
                .onChange(of: folderFocused) { _, focused in
                    if !focused { renameFolder(onReturn: false) }
                }
            LabeledContent {
                Text(storage)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } label: {
                Text(L("Screenshots"))
            }
        } header: {
            Text(L("Location"))
        } footer: {
            Text(L("Rename or move it here, or in the Finder: Snapfly finds it again."))
                .foregroundStyle(.secondary)
        }
    }

    private var storage: String {
        let total = WorkspaceStats.total(workspace.tallies)
        guard total.count > 0 else { return L("None yet") }
        let size = ByteCountFormatter.string(fromByteCount: total.bytes, countStyle: .file)
        return (total.count == 1 ? L("1 screenshot") : String(format: L("%d screenshots"), total.count)) + " · " + size
    }

    private var categories: some View {
        Section {
            Picker(L("New screenshots go to"), selection: Binding(
                get: { workspace.config.defaultCategory.id },
                set: { workspace.setDefaultCategory($0) })
            ) {
                ForEach(workspace.config.categories) { category in
                    Text(category.name).tag(category.id)
                }
            }
            ForEach(workspace.config.categories) { category in
                CategoryRow(workspace: workspace, category: category,
                            first: category.id == workspace.config.categories.first?.id,
                            last: category.id == workspace.config.categories.last?.id)
            }
            HStack {
                TextField(L("New category"), text: $newCategory, prompt: Text(L("Name")))
                    .onSubmit(add)
                Button(L("Add"), action: add)
                    .disabled(WorkspaceNames.clean(newCategory) == nil)
            }
            LabeledContent {
                SettingsButton(L("Restore Defaults")) { workspace.restoreCategories() }
            } label: {
                Text(L("Order and visibility"))
                Text(L("Shows every category again, in the usual order"))
            }
        } header: {
            Text(L("Categories"))
        } footer: {
            Text(L("Each category is a folder. Removing one moves its screenshots to Unsorted and deletes nothing. A hidden category stays in the Finder."))
                .foregroundStyle(.secondary)
        }
    }

    private func add() {
        guard WorkspaceNames.clean(newCategory) != nil else { return }
        workspace.addCategory(newCategory)
        newCategory = ""
    }

    private var danger: some View {
        Section {
            LabeledContent {
                Button(role: .destructive) { workspace.confirmDelete() } label: {
                    Text(L("Delete…")).frame(minWidth: SettingsButton.width)
                }
                .disabled(workspace.busy)
            } label: {
                Text(L("Delete the workspace"))
                Text(L("Moves its screenshots to the Trash, after asking. Other files in it stay."))
            }
        } footer: {
            Text(L("To stop using the workspace and keep everything, turn it off above."))
                .foregroundStyle(.secondary)
        }
    }
}

/// One category: its name, how many screenshots it holds, and the ways to
/// order, hide and remove it.
private struct CategoryRow: View {
    @ObservedObject var workspace: Workspace
    let category: WorkspaceCategory
    let first: Bool
    let last: Bool
    @State private var name = ""
    /// The name last tried, so leaving the field after Return, or after a
    /// name refused, does not try it again.
    @State private var triedName = ""
    @FocusState private var focused: Bool

    private var isDefault: Bool { workspace.config.defaultID == category.id }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: category.hidden ? "folder" : "folder.fill")
                .foregroundStyle(category.hidden ? .tertiary : .secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            TextField(L("Name"), text: $name)
                .labelsHidden()
                .textFieldStyle(.plain)
                .foregroundStyle(category.hidden ? .secondary : .primary)
                .focused($focused)
                .onSubmit { rename(onReturn: true) }
                .onChange(of: focused) { _, now in
                    if !now { rename(onReturn: false) }
                }
            if let tally = workspace.tallies[category.id], tally.count > 0 {
                Text("\(tally.count)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(tally.count == 1 ? L("1 screenshot") : String(format: L("%d screenshots"), tally.count))
            }
            tool(category.hidden ? "eye.slash" : "eye", category.hidden ? L("Show Category") : L("Hide Category")) {
                workspace.hideCategory(category.id, !category.hidden)
            }
            .disabled(isDefault && !category.hidden)
            tool("arrow.up", L("Move Up")) { workspace.moveCategory(category.id, by: -1) }
                .disabled(first)
            tool("arrow.down", L("Move Down")) { workspace.moveCategory(category.id, by: 1) }
                .disabled(last)
            tool("minus.circle", L("Remove Category")) { workspace.removeCategory(category.id) }
                .disabled(category.isUnsorted)
        }
        .onAppear { name = category.name }
        .onChange(of: category.name) { _, new in name = new }
        // A name typed and left, as the pane closes, is kept too.
        .onDisappear { rename(onReturn: false) }
    }

    /// The name as typed: on Return, and once the field is left, unless
    /// that name was tried already. An empty name or the same one changes
    /// nothing, and the field shows the name again.
    private func rename(onReturn: Bool) {
        guard let cleaned = WorkspaceNames.clean(name), cleaned != category.name else {
            name = category.name
            return
        }
        guard onReturn || name != triedName else { return }
        triedName = name
        workspace.renameCategory(category.id, to: name)
    }

    private func tool(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }
}
