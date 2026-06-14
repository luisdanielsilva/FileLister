import SwiftUI

// Include/exclude rule editor shown from the toolbar "Filters" button (#18).
// Rules are global + persistent and apply to every search (local & remote).
struct ScanFiltersPopover: View {
    @ObservedObject private var filters = ScanFilters.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search Filters").font(.system(size: 13, weight: .semibold))
            Text("Applied to every search — local Files, Folders, Photos, and remote. Takes effect on the next search.")
                .font(.system(size: 10)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            field("Exclude folders named", "node_modules, .git, Library", $filters.excludeFolders,
                  "Comma-separated; the whole subtree is skipped.")
            field("Only include extensions", "jpg, png, pdf   (empty = all)", $filters.includeExtensions,
                  "When set, only these extensions are scanned.")
            field("Exclude extensions", "tmp, log, ds_store", $filters.excludeExtensions,
                  "Skipped. Exclude wins over include.")

            HStack {
                Button("Clear all") {
                    filters.excludeFolders = ""
                    filters.includeExtensions = ""
                    filters.excludeExtensions = ""
                }
                .controlSize(.small).disabled(!filters.isActive)
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 330)
    }

    @ViewBuilder
    private func field(_ title: String, _ placeholder: String, _ text: Binding<String>, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11, weight: .medium))
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).font(.system(size: 11))
            Text(hint).font(.system(size: 9)).foregroundColor(.secondary)
        }
    }
}
