import SwiftUI

struct CloudFilesView: View {
    @ObservedObject var engine: OneDriveEngine
    @ObservedObject var auth: OneDriveAuth

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
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("OneDrive duplicates (\(engine.groups.count)):").font(.caption).fontWeight(.bold)
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
                    Button(action: { engine.deleteAll(auth: auth) }) {
                        Label("Delete all duplicates", systemImage: "trash").font(.system(size: 10, weight: .bold))
                    }.buttonStyle(.bordered).controlSize(.small)
                }
                .padding(.horizontal).padding(.vertical, 8).foregroundColor(.secondary)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(engine.groups) { group in
                            groupCard(group)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private func groupCard(_ group: CloudDupGroup) -> some View {
        let live = group.files.filter { !engine.deletedIDs.contains($0.id) }
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc").foregroundColor(.blue)
                Text(group.name).fontWeight(.bold).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Text("(\(byteString(group.sizeBytes)))").font(.caption2).foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive").font(.system(size: 8))
                    Text("Save \(byteString(group.reclaimable(excluding: engine.deletedIDs)))").font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.green.opacity(0.4), lineWidth: 1))
                Text("\(live.count) copies").font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(live.count > 1 ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                    .foregroundColor(live.count > 1 ? .blue : .green).cornerRadius(3)
                Button(action: { engine.deleteDuplicates(in: group, auth: auth) }) {
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
                HStack(spacing: 8) {
                    Image(systemName: isDeleted ? "checkmark.circle.fill" : "cloud")
                        .font(.system(size: 9)).foregroundColor(isDeleted ? .red : .blue.opacity(0.6))
                    Text(file.fullPath)
                        .font(.system(size: 10, design: .monospaced))
                        .strikethrough(isDeleted)
                        .foregroundColor(isDeleted ? .secondary : .primary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if let web = file.webURL, let url = URL(string: web), !isDeleted {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            Image(systemName: "arrow.up.forward.square").font(.system(size: 9)).foregroundColor(.gray)
                        }.buttonStyle(.plain).help("Open in OneDrive")
                    }
                }
                .padding(.leading, 12)
            }
        }
        .padding(6).background(live.count > 1 ? Color.orange.opacity(0.08) : Color.green.opacity(0.05)).cornerRadius(4)
    }

    private func byteString(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024, mb = kb / 1024, gb = mb / 1024
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", kb)
    }
}
