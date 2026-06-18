import SwiftUI
import ImageIO
import AppKit

// Thumbnail for a OneDrive photo, decoded from the cached thumbnail data.
struct CloudPhotoThumb: View {
    let photoID: String
    let data: Data?
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.gray.opacity(0.12))
                Image(systemName: "photo").foregroundColor(.gray.opacity(0.4))
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .task(id: photoID) { image = await Self.decode(data, maxPixel: Int(size * 2)) }
    }

    static func decode(_ data: Data?, maxPixel: Int) async -> NSImage? {
        guard let data else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let opts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
    }
}

struct CloudPhotosView: View {
    @ObservedObject var engine: RemoteEngine
    @ObservedObject private var scanFilters = ScanFilters.shared
    @State private var sizeFilter = SizeFilter()
    @State private var confirmGroups: [CloudPhotoGroup]? = nil   // non-nil → confirmation sheet
    @State private var confirmTitle = ""

    // Post-search filters: size (group shown if any photo in range) + include/exclude
    // (per-photo; keep 2+ survivors; reassign keeper if it was filtered out).
    private var displayedGroups: [CloudPhotoGroup] {
        var groups = engine.photoGroups
        if sizeFilter.isActive {
            groups = groups.filter { g in g.photos.contains { sizeFilter.contains($0.size) } }
        }
        if scanFilters.isActive {
            groups = groups.compactMap { g in
                let kept = g.photos.filter { scanFilters.allows(fullPath: $0.fullPath) }
                guard kept.count >= 2 else { return nil }
                var copy = g
                copy.photos = kept
                if !kept.contains(where: { $0.id == copy.keeperID }) { copy.keeperID = kept[0].id }
                return copy
            }
        }
        return groups
    }

    var body: some View {
        if engine.isScanning {
            VStack(spacing: 14) {
                ProgressView(value: engine.progress).progressViewStyle(.linear).frame(width: 280)
                Text(engine.status).font(.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle).frame(width: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if engine.photoGroups.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 48)).foregroundColor(.gray.opacity(0.25))
                Text("Similar Photos in OneDrive").font(.title3).fontWeight(.semibold)
                Text(engine.status).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let groups = displayedGroups
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Similar photo groups (\(sizeFilter.isActive || scanFilters.isActive ? "\(groups.count) of \(engine.photoGroups.count)" : "\(engine.photoGroups.count)")):")
                        .font(.caption).fontWeight(.bold)
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
                    Button(action: { confirmGroups = groups; confirmTitle = "Delete All Non-Keepers" }) {
                        Label("Delete all non-keepers", systemImage: "trash").font(.system(size: 10, weight: .bold)).foregroundColor(.red)
                    }.buttonStyle(.bordered).controlSize(.small).disabled(groups.isEmpty)
                }
                .padding(.horizontal).padding(.vertical, 8).foregroundColor(.secondary)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(groups) { group in groupCard(group) }
                    }
                    .padding(.horizontal)
                }
            }
            .sheet(item: Binding(get: { confirmGroups.map { IdentifiableGroups(groups: $0) } },
                                 set: { if $0 == nil { confirmGroups = nil } })) { wrapper in
                CloudPhotoDeleteSheet(engine: engine, groups: wrapper.groups, title: confirmTitle,
                                      onConfirm: { engine.recycleNonKeeperPhotos(in: wrapper.groups); confirmGroups = nil },
                                      onCancel: { confirmGroups = nil })
            }
        }
    }

    @ViewBuilder
    private func groupCard(_ group: CloudPhotoGroup) -> some View {
        let liveTargets = group.photos.filter { $0.id != group.keeperID && !engine.deletedIDs.contains($0.id) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up").foregroundColor(.indigo)
                Text("\(group.photos.count) similar photos").font(.system(size: 12, weight: .bold))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive").font(.system(size: 8))
                    Text("Save \(cloudByteString(group.reclaimableBytes(excluding: engine.deletedIDs)))").font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.green.opacity(0.4), lineWidth: 1))
                Button(action: { confirmGroups = [group]; confirmTitle = "Delete Other Copies" }) {
                    HStack(spacing: 4) { Image(systemName: "trash"); Text("Delete others") }
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.red)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.red.opacity(0.08)).cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.red.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain).disabled(liveTargets.isEmpty)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(group.photos) { photo in photoCell(photo, in: group) }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(Color.indigo.opacity(0.05)).cornerRadius(8)
    }

    @ViewBuilder
    private func photoCell(_ photo: CloudPhotoInfo, in group: CloudPhotoGroup) -> some View {
        let isKeeper = photo.id == group.keeperID
        let isDeleted = engine.deletedIDs.contains(photo.id)
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                CloudPhotoThumb(photoID: photo.id, data: engine.photoThumbnailData[photo.id], size: 130)
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(isKeeper ? Color.green : (isDeleted ? Color.gray : Color.red.opacity(0.5)),
                                lineWidth: isKeeper ? 2.5 : 1.5))
                Text(isKeeper ? "KEEP" : (isDeleted ? "DELETED" : "DELETE"))
                    .font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(isKeeper ? Color.green : (isDeleted ? Color.gray : Color.red))
                    .cornerRadius(4).padding(4)
            }
            .opacity(isDeleted ? 0.4 : 1)

            Text(photo.name).font(.system(size: 9)).lineLimit(1).truncationMode(.middle).frame(width: 130)
            Text("\(photo.pixelWidth)×\(photo.pixelHeight) · \(cloudByteString(photo.size))")
                .font(.system(size: 8)).foregroundColor(.secondary)

            if !isDeleted {
                HStack(spacing: 6) {
                    if !isKeeper {
                        Button("Keep this") { engine.setPhotoKeeper(photo.id, in: group.id) }
                            .buttonStyle(.bordered).controlSize(.mini)
                    }
                    if let web = photo.webURL, let url = URL(string: web) {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            Image(systemName: "arrow.up.forward.square").font(.system(size: 9))
                        }.buttonStyle(.borderless).help("Open in OneDrive")
                    }
                }
            }
        }
        .frame(width: 134)
    }
}

// Wrapper so an array of groups can drive a `.sheet(item:)`.
private struct IdentifiableGroups: Identifiable {
    let id = UUID()
    let groups: [CloudPhotoGroup]
}

// Confirmation before recycling non-keeper photos (one group or all).
struct CloudPhotoDeleteSheet: View {
    @ObservedObject var engine: RemoteEngine
    let groups: [CloudPhotoGroup]
    let title: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var targets: [CloudPhotoInfo] {
        groups.flatMap { g in g.photos.filter { $0.id != g.keeperID && !engine.deletedIDs.contains($0.id) } }
    }
    private var savings: Int64 { targets.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "trash").font(.title2).foregroundColor(.red)
                Text(title).font(.title2).fontWeight(.bold)
                Spacer()
                Label(cloudByteString(savings) + " freed", systemImage: "internaldrive")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(.green)
            }

            Divider()

            Text("\(targets.count) photo(s) moved to the OneDrive recycle bin · the best copy in each group is kept.")
                .font(.system(size: 11, weight: .semibold))

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(targets) { p in
                        HStack(spacing: 6) {
                            Image(systemName: "trash").foregroundColor(.red).font(.system(size: 9))
                            Text(p.fullPath).font(.system(size: 10, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(cloudByteString(p.size)).font(.caption2).foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 6)
                    }
                }
            }
            .frame(maxHeight: 240)

            Divider()

            HStack {
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Spacer()
                Button(action: onConfirm) {
                    HStack(spacing: 6) { Image(systemName: "trash"); Text("Delete \(targets.count) Photo(s)") }
                        .fontWeight(.semibold).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.red).cornerRadius(8)
                }.buttonStyle(.plain).disabled(targets.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}
