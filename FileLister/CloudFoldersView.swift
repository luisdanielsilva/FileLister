import SwiftUI

// OneDrive Folders mode (detection only): shows clusters of folders that share
// most of their content, with per-file / per-group delete reused from Files mode.
struct CloudFoldersView: View {
    @ObservedObject var engine: RemoteEngine
    @Binding var selectedCloudID: String?
    var onMergeCluster: (CloudFolderDupGroup) -> Void
    @State private var collapsedClusterIDs: Set<UUID> = []

    var body: some View {
        if engine.isScanning {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text(engine.status).font(.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle).frame(width: 380)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if engine.folderGroups.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "folder").font(.system(size: 48)).foregroundColor(.gray.opacity(0.25))
                Text("Duplicate Folders in OneDrive").font(.title3).fontWeight(.semibold)
                Text(engine.status).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("OneDrive folder clusters (\(engine.folderGroups.count)):").font(.caption).fontWeight(.bold)
                    Text("Space to preview · ← → to move").font(.system(size: 8, weight: .bold)).foregroundColor(.blue)
                    if engine.hitLimit {
                        Text("preview limit reached").font(.system(size: 8, weight: .bold)).foregroundColor(.orange)
                            .padding(.horizontal, 4).padding(.vertical, 1).background(Color.orange.opacity(0.12)).cornerRadius(3)
                    }
                    Spacer()
                    if let logURL = engine.lastLogURL {
                        Button(action: { NSWorkspace.shared.activateFileViewerSelecting([logURL]) }) {
                            Label("Reveal Log", systemImage: "doc.text.magnifyingglass").font(.system(size: 10))
                        }.buttonStyle(.bordered).controlSize(.small)
                    }
                    Button(action: { engine.deleteAllFolders() }) {
                        Label("Delete all duplicates", systemImage: "trash").font(.system(size: 10, weight: .bold))
                    }.buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.horizontal).padding(.vertical, 8).foregroundColor(.secondary)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(engine.folderGroups) { cluster in
                            clusterCard(cluster)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private func clusterCard(_ cluster: CloudFolderDupGroup) -> some View {
        let isCollapsed = collapsedClusterIDs.contains(cluster.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(action: {
                    if isCollapsed { collapsedClusterIDs.remove(cluster.id) }
                    else { collapsedClusterIDs.insert(cluster.id) }
                }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.blue).frame(width: 12)
                }
                .buttonStyle(.plain)
                Image(systemName: "folder.fill").foregroundColor(.blue)
                Text(cluster.keepName).fontWeight(.bold).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Text("\(cluster.folders.count) folders").font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.blue.opacity(0.1)).foregroundColor(.blue).cornerRadius(3)
                Text("\(Int(cluster.matchRatio * 100))% match").font(.system(size: 9, weight: .medium))
                    .foregroundColor(.purple)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive").font(.system(size: 8))
                    Text("Save \(cloudByteString(cluster.reclaimable(excluding: engine.deletedIDs)))").font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.green.opacity(0.4), lineWidth: 1))

                Button(action: { onMergeCluster(cluster) }) {
                    HStack(spacing: 4) {
                        Image(systemName: engine.safeMergeToNewFolder ? "doc.on.doc" : "arrow.triangle.merge")
                        Text(engine.safeMergeToNewFolder ? "Merge to New" : "Merge & Clean")
                    }
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.indigo)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.08)).cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.indigo.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(engine.isScanning)
            }

            if !isCollapsed {
            // Folders in the cluster (keep marked).
            ForEach(Array(cluster.folders.enumerated()), id: \.element) { idx, folder in
                HStack(spacing: 6) {
                    Image(systemName: idx == 0 ? "checkmark.circle.fill" : "folder")
                        .font(.system(size: 9)).foregroundColor(idx == 0 ? .green : .secondary)
                    Text(folder.isEmpty ? "/" : folder)
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.primary)
                        .lineLimit(1).truncationMode(.middle)
                    if idx == 0 {
                        Text("keep").font(.system(size: 8, weight: .bold)).foregroundColor(.green)
                    }
                    Spacer()
                }
                .padding(.leading, 6)
            }

            Divider()

            // Shared content (per-group / per-file delete reused from Files mode).
            ForEach(cluster.matchedGroups) { group in
                CloudGroupCard(engine: engine, group: group, selectedCloudID: $selectedCloudID)
            }
            }
        }
        .padding(6).background(Color.orange.opacity(0.08)).cornerRadius(4)
    }
}
