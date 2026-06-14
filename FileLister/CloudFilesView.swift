import SwiftUI

// Small circular download-progress ring.
struct ProgressRing: View {
    let progress: Double   // 0…1
    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)
        }
    }
}

struct CloudFilesView: View {
    @ObservedObject var engine: RemoteEngine
    @Binding var selectedCloudID: String?
    @State private var showingDeleteAll = false
    @State private var sizeFilter = SizeFilter()

    private var filteredGroups: [CloudDupGroup] {
        guard sizeFilter.isActive else { return engine.groups }
        return engine.groups.filter { sizeFilter.contains($0.sizeBytes) }
    }

    private var filterActive: Bool { sizeFilter.isActive }

    var body: some View {
        if engine.isScanning {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(engine.status).font(.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle).frame(width: 380)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if engine.groups.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "cloud").font(.system(size: 48)).foregroundColor(.gray.opacity(0.25))
                Text("Duplicate Files in OneDrive").font(.title3).fontWeight(.semibold)
                Text(engine.status).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let filtered = filteredGroups
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack {
                    Text("OneDrive duplicates (\(filterActive ? "\(filtered.count) of \(engine.groups.count)" : "\(engine.groups.count)")):")
                        .font(.caption).fontWeight(.bold)
                    Text("Space to preview · ← → to move").font(.system(size: 8, weight: .bold)).foregroundColor(.blue)
                    if engine.hitLimit {
                        Text("scan limit reached").font(.system(size: 8, weight: .bold)).foregroundColor(.orange)
                            .padding(.horizontal, 4).padding(.vertical, 1).background(Color.orange.opacity(0.12)).cornerRadius(3)
                            .help("The OneDrive scan stopped at the file/size limit. Raise or remove it in Settings → OneDrive.")
                    }
                    Spacer()
                    SizeFilterBar(filter: $sizeFilter)
                    Divider().frame(height: 16)
                    if let logURL = engine.lastLogURL {
                        Button(action: { NSWorkspace.shared.activateFileViewerSelecting([logURL]) }) {
                            Label("Reveal Log", systemImage: "doc.text.magnifyingglass").font(.system(size: 10))
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                    Button(action: { showingDeleteAll = true }) {
                        Label("Delete all duplicates", systemImage: "trash").font(.system(size: 10, weight: .bold))
                    }.buttonStyle(.bordered).controlSize(.small).disabled(filtered.isEmpty)
                }
                .padding(.horizontal).padding(.vertical, 8).foregroundColor(.secondary)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { group in
                            CloudGroupCard(engine: engine, group: group, selectedCloudID: $selectedCloudID)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .sheet(isPresented: $showingDeleteAll) {
                CloudDeleteAllSheet(engine: engine, groups: filtered, onDeleteAll: { engine.deleteGroups(filtered) })
            }
            // Keep the size-filter text fields from holding keyboard focus, so Space
            // (preview) and the arrow keys reach their shortcuts instead of the field.
            .onAppear { resignTextFocus() }
            .onChange(of: selectedCloudID) { _, _ in resignTextFocus() }
        }
    }

    private func resignTextFocus() {
        DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
    }

}

// One duplicate-content group: header (save/copies/delete) + per-file rows.
// Shared by the Files view and the Folders (cluster) view.
struct CloudGroupCard: View {
    @ObservedObject var engine: RemoteEngine
    let group: CloudDupGroup
    @Binding var selectedCloudID: String?
    @State private var showingDeleteConfirm = false

    var body: some View {
        let live = group.files.filter { !engine.deletedIDs.contains($0.id) }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc").foregroundColor(.blue)
                Text(group.name).fontWeight(.bold).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Text("(\(cloudByteString(group.sizeBytes)))").font(.caption2).foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive").font(.system(size: 8))
                    Text("Save \(cloudByteString(group.reclaimable(excluding: engine.deletedIDs)))").font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.green.opacity(0.4), lineWidth: 1))
                Text("\(live.count) copies").font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(live.count > 1 ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                    .foregroundColor(live.count > 1 ? .blue : .green).cornerRadius(3)
                Button(action: { showingDeleteConfirm = true }) {
                    HStack(spacing: 4) { Image(systemName: "trash"); Text("Delete dupes") }
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.red)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.red.opacity(0.08)).cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.red.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain).disabled(live.count <= 1)
            }
            ForEach(group.files, id: \.id) { file in
                let isDeleted = engine.deletedIDs.contains(file.id)
                let isSelected = selectedCloudID == file.id
                HStack(spacing: 8) {
                    if engine.previewingID == file.id {
                        ProgressRing(progress: engine.previewProgress).frame(width: 14, height: 14)
                    } else {
                        Image(systemName: isDeleted ? "checkmark.circle.fill" : "cloud")
                            .font(.system(size: 9)).foregroundColor(isDeleted ? .red : .blue.opacity(0.6))
                            .frame(width: 14, height: 14)
                    }
                    Text(file.fullPath)
                        .font(.system(size: 10, design: .monospaced))
                        .strikethrough(isDeleted)
                        .foregroundColor(isDeleted ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if !isDeleted {
                        if let web = file.webURL, let url = URL(string: web) {
                            Button(action: { NSWorkspace.shared.open(url) }) {
                                Image(systemName: "arrow.up.forward.square").font(.system(size: 9)).foregroundColor(.gray)
                            }.buttonStyle(.plain).help("Open in OneDrive")
                        }
                        Button(action: { engine.deleteFile(file, in: group) }) {
                            Image(systemName: live.count > 1 ? "trash" : "lock.fill")
                                .font(.system(size: 9)).foregroundColor(live.count > 1 ? .red : .green.opacity(0.5))
                        }
                        .buttonStyle(.plain).disabled(live.count <= 1)
                        .help(live.count > 1 ? "Move this copy to the OneDrive recycle bin" : "Last copy — kept safe")
                    }
                }
                .padding(.vertical, 2).padding(.horizontal, 6)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                .cornerRadius(4)
                .contentShape(Rectangle())
                .onTapGesture { if !isDeleted { selectedCloudID = file.id } }
                .padding(.leading, 6)
            }
        }
        .padding(6).background(live.count > 1 ? Color.orange.opacity(0.08) : Color.green.opacity(0.05)).cornerRadius(4)
        .sheet(isPresented: $showingDeleteConfirm) {
            CloudDeleteGroupSheet(engine: engine, group: group, onDelete: { engine.deleteDuplicates(in: group) })
        }
    }
}

func cloudByteString(_ bytes: Int64) -> String {
    let kb = Double(bytes) / 1024, mb = kb / 1024, gb = mb / 1024
    if gb >= 1 { return String(format: "%.2f GB", gb) }
    if mb >= 1 { return String(format: "%.1f MB", mb) }
    return String(format: "%.0f KB", kb)
}
