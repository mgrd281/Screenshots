import SwiftUI
import UniformTypeIdentifiers

/// On the Scan tab, under the scan card: "PDF erstellen und bearbeiten", a
/// white card with two tiles, Merge (photos, scans and PDFs into one file)
/// and Open PDF (a PDF from Files, to put its pages in order and cover them).
struct PDFStartCard: View {
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Create and Edit PDFs"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { tiles }
                VStack(spacing: 12) { tiles }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SnapflyTokens.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            ProjectStore.shared.start(.files([url]))
        }
    }

    @ViewBuilder private var tiles: some View {
        tile(L("Merge"), detail: L("Photos, scans and PDFs into one file"), symbol: "doc.on.doc", id: "project-merge") {
            ProjectStore.shared.start()
        }
        tile(L("Open PDF"), detail: L("Put pages in order and cover them"), symbol: "doc.text.magnifyingglass",
             id: "project-open-pdf") {
            choosing = true
        }
    }

    private func tile(_ title: String, detail: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SnapflyTokens.protectTint)
                    .frame(width: 40, height: 40)
                    .background(SnapflyTokens.projectTile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(id)
    }
}

/// "Zuletzt bearbeitet": the projects changed last, each with its name, how
/// many pages it has and when it was changed; a tap goes on where it was
/// left, holding it offers Delete.
struct RecentProjects: View {
    @ObservedObject private var store = ProjectStore.shared
    /// How many show.
    private static let shown = 5

    var body: some View {
        let recent = Array(store.projects.filter { !$0.pages.isEmpty }.prefix(Self.shown))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Recently Edited"))
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, project in
                        if index > 0 { Divider().padding(.leading, 64) }
                        row(project)
                    }
                }
                .background(SnapflyTokens.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func row(_ project: PDFProject) -> some View {
        Button { store.open(project.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SnapflyTokens.protectTint)
                    .frame(width: 36, height: 36)
                    .background(SnapflyTokens.projectTile, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(ProjectNaming.pages(project.pages.count) + " · " + project.modified.formatted(.relative(presentation: .named)))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation(.easeOut(duration: 0.2)) { store.delete(project.id) }
            } label: {
                Label(L("Delete"), systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: L("Delete")) { store.delete(project.id) }
        .accessibilityIdentifier("project-recent")
    }
}
