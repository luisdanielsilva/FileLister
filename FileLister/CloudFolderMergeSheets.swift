import SwiftUI

// Preview + confirm for a single OneDrive folder cluster. Reused for the
// "Review One-by-One" walkthrough (when the walkthrough callbacks are supplied).
struct CloudClusterSheet: View {
    @ObservedObject var engine: RemoteEngine
    let cluster: CloudFolderDupGroup
    @Binding var selectedCloudID: String?
    var progressLabel: String? = nil
    var copyDestinationName: String? = nil  // set → "copy to new folder" (originals kept) mode
    var onMerge: (() -> Void)? = nil        // single-cluster mode
    var onApproveNext: (() -> Void)? = nil  // walkthrough mode
    var onSkip: (() -> Void)? = nil         // walkthrough mode
    let onClose: () -> Void

    private var isWalkthrough: Bool { onApproveNext != nil }
    private var isCopy: Bool { copyDestinationName != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: isCopy ? "doc.on.doc" : "arrow.triangle.merge").font(.title2).foregroundColor(.indigo)
                Text(isCopy ? "Copy Merged Folder" : "Merge Folder Cluster").font(.title2).fontWeight(.bold)
                Spacer()
                if let label = progressLabel {
                    Text(label).font(.system(size: 11)).foregroundColor(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.1)).cornerRadius(4)
                }
                Text("\(Int(cluster.matchRatio * 100))% match").font(.system(size: 11, weight: .bold)).foregroundColor(.purple)
            }

            Divider()

            // Folders: keep + the ones that go to the recycle bin.
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 11))
                    Text("Keep").font(.system(size: 10, weight: .bold)).foregroundColor(.green)
                    Text(cluster.keepFolder.isEmpty ? "/" : cluster.keepFolder)
                        .font(.system(size: 11, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                }
                ForEach(cluster.otherFolders, id: \.self) { other in
                    HStack(spacing: 6) {
                        Image(systemName: isCopy ? "folder" : "trash").foregroundColor(isCopy ? .secondary : .red).font(.system(size: 10))
                        Text(other).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Text(isCopy
                     ? "Originals kept · merged copy written to \"\(copyDestinationName ?? "")\""
                     : "\(cluster.otherFolders.count) folder(s) → OneDrive recycle bin")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }

            // What the merge does.
            HStack(spacing: 16) {
                Label(isCopy
                      ? "\(cluster.filesToMove.count) file(s) copied into the new folder"
                      : "\(cluster.filesToMove.count) unique file(s) moved into keep",
                      systemImage: "arrow.right.doc.on.clipboard")
                    .font(.system(size: 10)).foregroundColor(.blue)
                if !isCopy {
                    Label("Save \(cloudByteString(cluster.reclaimable(excluding: engine.deletedIDs)))", systemImage: "internaldrive")
                        .font(.system(size: 10)).foregroundColor(.green)
                }
            }

            MergePieChart(composition: mergeComposition(cluster))

            Divider()

            ScrollView {
                LazyVStack(spacing: 8) {
                    if !cluster.filesToMove.isEmpty {
                        Text(isCopy ? "Files copied into the new folder" : "Unique files moved into keep").font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(cluster.filesToMove) { f in
                            HStack(spacing: 6) {
                                Image(systemName: "doc").font(.system(size: 9)).foregroundColor(.blue.opacity(0.6))
                                Text(f.fullPath).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(cloudByteString(f.size)).font(.caption2).foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                        }
                    }
                    if !isCopy && !cluster.matchedGroups.isEmpty {
                        Text("Duplicate content removed").font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(cluster.matchedGroups) { group in
                            CloudGroupCard(engine: engine, group: group, selectedCloudID: $selectedCloudID)
                        }
                    }
                }
            }
            .frame(maxHeight: 280)

            Divider()

            // Footer
            HStack {
                Button("Cancel", action: onClose).buttonStyle(.bordered)
                Spacer()
                if isWalkthrough {
                    Button("Skip", action: { onSkip?() }).buttonStyle(.bordered)
                    Button(action: { onApproveNext?() }) {
                        HStack(spacing: 6) { Image(systemName: "checkmark"); Text("Approve & Next") }
                            .fontWeight(.semibold).foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.indigo).cornerRadius(8)
                    }.buttonStyle(.plain)
                } else {
                    Button(action: { onMerge?() }) {
                        HStack(spacing: 6) {
                            Image(systemName: isCopy ? "doc.on.doc" : "arrow.triangle.merge")
                            Text(isCopy ? "Copy to New Folder" : "Merge & Clean")
                        }
                            .fontWeight(.semibold).foregroundColor(.white)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Color.indigo).cornerRadius(8)
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}

// Confirm merging every detected OneDrive folder cluster, with the shared
// naming rule (reused from the local scanner) applied when renaming is on.
struct CloudMergeAllSheet: View {
    @ObservedObject var engine: RemoteEngine
    @ObservedObject var scanner: FileScanner
    var copyDestinationName: String? = nil   // set → "copy to new folder" (originals kept) mode
    let onMergeAll: () -> Void
    let onCancel: () -> Void

    private var isCopy: Bool { copyDestinationName != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: isCopy ? "doc.on.doc" : "arrow.triangle.merge").font(.title2).foregroundColor(.indigo)
                Text(isCopy ? "Copy All Merged Folders" : "Merge All Folder Clusters").font(.title2).fontWeight(.bold)
                Spacer()
                Text("\(engine.folderGroups.count) clusters")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.indigo.opacity(0.1)).cornerRadius(4)
            }

            Divider()

            MergePieChart(composition: mergeComposition(engine.folderGroups))

            Divider()

            if engine.renameKeptFolder {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Naming rule (applied when renaming the kept folder)").font(.system(size: 12, weight: .semibold))
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Toggle("", isOn: Binding(
                                get: { scanner.mergeNamePosition == .prefix },
                                set: { scanner.mergeNamePosition = $0 ? .prefix : .suffix }
                            )).toggleStyle(.checkbox).labelsHidden()
                            Text("Prefix").font(.system(size: 12))
                        }
                        HStack(spacing: 6) {
                            Toggle("", isOn: Binding(
                                get: { scanner.mergeNamePosition == .suffix },
                                set: { scanner.mergeNamePosition = $0 ? .suffix : .prefix }
                            )).toggleStyle(.checkbox).labelsHidden()
                            Text("Suffix").font(.system(size: 12))
                        }
                        HStack(spacing: 6) {
                            Text("Content:").font(.system(size: 12)).foregroundColor(.secondary)
                            TextField("e.g. merged", text: $scanner.mergeNameContent)
                                .textFieldStyle(.roundedBorder).frame(width: 100).font(.system(size: 12))
                        }
                        HStack(spacing: 6) {
                            Text("Separator:").font(.system(size: 12)).foregroundColor(.secondary)
                            TextField("", text: $scanner.mergeNameSeparator)
                                .textFieldStyle(.roundedBorder).frame(width: 50).font(.system(size: 12))
                        }
                    }
                }
                Divider()
            }

            Text("Clusters to merge").font(.system(size: 12, weight: .semibold))
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(engine.folderGroups) { fg in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder.fill").foregroundColor(.green).font(.system(size: 10))
                                    Text(fg.keepName).font(.system(size: 11, weight: .semibold)).foregroundColor(.green)
                                    Text("← \(fg.otherFolders.count) folder(s)").foregroundColor(.secondary).font(.system(size: 10))
                                }
                                if engine.renameKeptFolder {
                                    let preview = scanner.computeMergedFolderName(folderA: fg.keepFolder, folderB: fg.otherFolders.first ?? fg.keepFolder)
                                    HStack(spacing: 4) {
                                        Image(systemName: "pencil").foregroundColor(.secondary).font(.system(size: 9))
                                        Text(preview).font(.system(size: 11)).foregroundColor(.secondary)
                                    }
                                }
                            }
                            Spacer()
                            Text("\(Int(fg.matchRatio * 100))%")
                                .font(.system(size: 9, weight: .bold)).foregroundColor(.indigo)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.indigo.opacity(0.1)).cornerRadius(3)
                        }
                        .padding(8).background(Color.indigo.opacity(0.04)).cornerRadius(6)
                    }
                }
            }
            .frame(maxHeight: 220)

            Text(isCopy
                 ? "A new merged folder is created for each cluster inside \"\(copyDestinationName ?? "")\". Originals are kept untouched — nothing is recycled."
                 : "Other folders in each cluster move to the OneDrive recycle bin after their unique files are merged into the kept folder.")
                .font(.system(size: 10)).foregroundColor(.secondary)

            Divider()

            HStack {
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Spacer()
                Button(action: onMergeAll) {
                    HStack(spacing: 6) {
                        Image(systemName: isCopy ? "doc.on.doc" : "arrow.triangle.merge")
                        Text(isCopy ? "Copy All to New Folder" : "Merge All & Clean")
                    }
                        .fontWeight(.semibold).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.indigo).cornerRadius(8)
                }.buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
