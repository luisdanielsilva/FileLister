import SwiftUI
import ImageIO
import AppKit

// Lazily-loaded downsampled thumbnail for a local image file.
struct PhotoThumb: View {
    let path: String
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
        .task(id: path) { image = await Self.load(path, maxPixel: Int(size * 2)) }
    }

    static func load(_ path: String, maxPixel: Int) async -> NSImage? {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let url = URL(fileURLWithPath: path)
                guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { cont.resume(returning: nil); return }
                let opts: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixel
                ]
                if let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) {
                    cont.resume(returning: NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)))
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

enum PhotoConfirmSheet: Identifiable {
    case group(PhotoGroup)
    case all
    var id: String { switch self { case .group(let g): return "g-\(g.id)"; case .all: return "all" } }
}

struct PhotosModeView: View {
    @ObservedObject var engine: PhotoEngine
    let hasFolders: Bool
    @Binding var selectedPhotoID: UUID?
    @State private var activeSheet: PhotoConfirmSheet?
    @State private var sizeFilter = SizeFilter()

    // A group is shown if at least one of its photos falls within the size range.
    private var displayedGroups: [PhotoGroup] {
        guard sizeFilter.isActive else { return engine.groups }
        return engine.groups.filter { g in g.photos.contains { sizeFilter.contains($0.sizeBytes) } }
    }

    var body: some View {
        if engine.isScanning {
            VStack(spacing: 14) {
                ProgressView(value: engine.progress)
                    .progressViewStyle(.linear).frame(width: 280)
                Text(engine.status).font(.caption).foregroundColor(.secondary)
                    .lineLimit(1).truncationMode(.middle).frame(width: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if engine.groups.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 48)).foregroundColor(.gray.opacity(0.25))
                Text("Duplicate Photos").font(.title3).fontWeight(.semibold)
                Text(hasFolders
                     ? "Press “Search for Duplicates” to find visually similar photos."
                     : "Add one or more folders, then press “Search for Duplicates”.")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let groups = displayedGroups
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Similar photo groups (\(sizeFilter.isActive ? "\(groups.count) of \(engine.groups.count)" : "\(engine.groups.count)")):")
                        .font(.caption).fontWeight(.bold)
                    Text("Space to preview · ← → to move").font(.system(size: 8, weight: .bold)).foregroundColor(.blue)
                    Spacer()
                    SizeFilterBar(filter: $sizeFilter)
                    Divider().frame(height: 16)
                    if let logURL = engine.lastLogURL {
                        Button(action: { NSWorkspace.shared.activateFileViewerSelecting([logURL]) }) {
                            Label("Reveal Log", systemImage: "doc.text.magnifyingglass").font(.system(size: 10))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                    actionButton(label: "Copy keepers to…", icon: "square.and.arrow.up.on.square", color: .green) { exportKeepers() }
                    actionButton(label: "Delete all non-keepers", icon: "trash", color: .red) { activeSheet = .all }
                }
                .padding(.horizontal).padding(.vertical, 8).foregroundColor(.secondary)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(groups) { group in
                            groupCard(group)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .group(let group):
                    PhotoDeleteConfirmSheet(
                        engine: engine,
                        group: group,
                        onConfirm: { engine.recycleNonKeepers(in: group); activeSheet = nil },
                        onCancel: { activeSheet = nil }
                    )
                case .all:
                    PhotoDeleteAllConfirmSheet(
                        engine: engine,
                        groups: displayedGroups,
                        onConfirm: { engine.recycleAllNonKeepers(in: displayedGroups); activeSheet = nil },
                        onCancel: { activeSheet = nil }
                    )
                }
            }
            // Keep the size-filter text fields from holding keyboard focus, so Space
            // (preview) and the arrow keys reach their shortcuts instead of the field.
            .onAppear { resignTextFocus() }
            .onChange(of: selectedPhotoID) { _, _ in resignTextFocus() }
        }
    }

    private func resignTextFocus() {
        DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) }
    }

    @ViewBuilder
    private func groupCard(_ group: PhotoGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up").foregroundColor(.indigo)
                Text("\(group.photos.count) similar photos").font(.system(size: 12, weight: .bold))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "internaldrive").font(.system(size: 8))
                    Text("Save \(byteString(group.reclaimableBytes))").font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.green.opacity(0.4), lineWidth: 1))
                Button(action: { activeSheet = .group(group) }) {
                    HStack(spacing: 4) { Image(systemName: "trash"); Text("Delete others") }
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.red)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.red.opacity(0.08)).cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.red.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(group.photos) { photo in
                        photoCell(photo, in: group)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(Color.indigo.opacity(0.05)).cornerRadius(8)
    }

    @ViewBuilder
    private func photoCell(_ photo: PhotoInfo, in group: PhotoGroup) -> some View {
        let isKeeper = photo.id == group.keeperID
        let isDeleted = engine.deletedPaths.contains(photo.fullPath)
        let isSelected = photo.id == selectedPhotoID
        VStack(spacing: 4) {
            ZStack(alignment: .topLeading) {
                PhotoThumb(path: photo.fullPath, size: 130)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isKeeper ? Color.green : (isDeleted ? Color.gray : Color.red.opacity(0.5)),
                                    lineWidth: isKeeper ? 2.5 : 1.5)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                            .padding(-2)
                    )
                    .onTapGesture { selectedPhotoID = photo.id }
                Text(isKeeper ? "KEEP" : (isDeleted ? "DELETED" : "DELETE"))
                    .font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(isKeeper ? Color.green : (isDeleted ? Color.gray : Color.red))
                    .cornerRadius(4).padding(4)
            }
            .opacity(isDeleted ? 0.4 : 1)

            Text(photo.name).font(.system(size: 9)).lineLimit(1).truncationMode(.middle).frame(width: 130)
            Text("\(photo.pixelWidth)×\(photo.pixelHeight) · \(byteString(photo.sizeBytes))")
                .font(.system(size: 8)).foregroundColor(.secondary)
            if let d = photo.captureDate {
                Text(Self.dateFormatter.string(from: d)).font(.system(size: 8)).foregroundColor(.secondary)
            }
            if !isKeeper {
                Text("\(engine.similarityToKeeper(photo, in: group))% match")
                    .font(.system(size: 8, weight: .medium)).foregroundColor(.indigo)
            }

            if !isDeleted {
                HStack(spacing: 6) {
                    if !isKeeper {
                        Button("Keep this") { engine.setKeeper(photo.id, in: group.id) }
                            .buttonStyle(.bordered).controlSize(.mini)
                    }
                    Button(action: { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: photo.fullPath)]) }) {
                        Image(systemName: "magnifyingglass").font(.system(size: 9))
                    }
                    .buttonStyle(.borderless).help("Reveal in Finder")
                }
            }
        }
        .frame(width: 134)
    }

    @ViewBuilder
    private func actionButton(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) { Image(systemName: icon); Text(label) }
                .font(.system(size: 10, weight: .bold)).foregroundColor(color)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(color.opacity(0.08)).cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(color.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func exportKeepers() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose where to copy the keeper photos. Their folder structure is replicated; the originals are not touched."
        panel.prompt = "Copy Keepers Here"
        if panel.runModal() == .OK, let url = panel.url { engine.copyKeepers(to: url, from: displayedGroups) }
    }

    private func byteString(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024, mb = kb / 1024, gb = mb / 1024
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", kb)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f
    }()
}

// Confirmation shown before deleting a group's non-keepers.
struct PhotoDeleteConfirmSheet: View {
    @ObservedObject var engine: PhotoEngine
    let group: PhotoGroup
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var keeper: PhotoInfo? { group.keeper }
    private var toDelete: [PhotoInfo] {
        group.photos.filter { $0.id != group.keeperID && !engine.deletedPaths.contains($0.fullPath) }
    }
    private var savings: Int { toDelete.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review deletion").font(.headline)
                    Text("\(toDelete.count) photo(s) will be moved to Trash · frees \(byteString(savings))")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let k = keeper {
                        Text("KEEP").font(.system(size: 9, weight: .bold)).foregroundColor(.green)
                        photoRow(k, accent: .green, diffAgainst: nil)
                    }
                    if !toDelete.isEmpty {
                        Text("DELETE").font(.system(size: 9, weight: .bold)).foregroundColor(.red).padding(.top, 4)
                        ForEach(toDelete) { p in
                            photoRow(p, accent: .red, diffAgainst: keeper)
                        }
                    }
                }
                .padding(14)
            }

            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(action: onConfirm) {
                    HStack(spacing: 6) { Image(systemName: "trash"); Text("Delete \(toDelete.count) & Keep best") }
                        .fontWeight(.semibold).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.red).cornerRadius(7)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(toDelete.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 660, height: 560)
    }

    @ViewBuilder
    private func photoRow(_ p: PhotoInfo, accent: Color, diffAgainst keeper: PhotoInfo?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            PhotoThumb(path: p.fullPath, size: 120)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent, lineWidth: 2))

            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(p.fullPath).font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                    .lineLimit(2).truncationMode(.middle)

                Divider().padding(.vertical, 2)

                attrRow("Resolution", "\(p.pixelWidth)×\(p.pixelHeight) (\(megapixels(p)))",
                        delta: keeper.flatMap { resolutionDelta(p, $0) })
                attrRow("File size", byteString(p.sizeBytes),
                        delta: keeper.flatMap { sizeDelta(p, $0) })
                attrRow("Capture date", p.captureDate.map { Self.df.string(from: $0) } ?? "—",
                        delta: nil)
                attrRow("Camera", p.cameraModel ?? "—", delta: cameraDelta(p, keeper))
                attrRow("GPS", p.gps != nil ? "yes" : "no", delta: nil)
                if let k = keeper {
                    attrRow("Visual match", "\(engine.similarityToKeeper(p, in: group))% to keeper", delta: nil)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(accent.opacity(0.05)).cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private func attrRow(_ label: String, _ value: String, delta: String?) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 10)).foregroundColor(.secondary).frame(width: 92, alignment: .leading)
            Text(value).font(.system(size: 11))
            if let delta {
                Text(delta).font(.system(size: 9, weight: .bold)).foregroundColor(.orange)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.orange.opacity(0.12)).cornerRadius(3)
            }
            Spacer()
        }
    }

    private func megapixels(_ p: PhotoInfo) -> String {
        String(format: "%.1f MP", Double(p.pixels) / 1_000_000)
    }
    private func resolutionDelta(_ p: PhotoInfo, _ k: PhotoInfo) -> String? {
        if p.pixels == k.pixels { return nil }
        return p.pixels < k.pixels ? "lower" : "higher"
    }
    private func sizeDelta(_ p: PhotoInfo, _ k: PhotoInfo) -> String? {
        if p.sizeBytes == k.sizeBytes { return nil }
        return p.sizeBytes < k.sizeBytes ? "smaller" : "larger"
    }
    private func cameraDelta(_ p: PhotoInfo, _ keeper: PhotoInfo?) -> String? {
        guard let k = keeper else { return nil }
        return p.cameraModel == k.cameraModel ? nil : "differs"
    }
    private func byteString(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024, mb = kb / 1024, gb = mb / 1024
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", kb)
    }
    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .medium; return f
    }()
}

// Two-segment donut (kept vs freed).
struct SpaceDonut: View {
    let keptFraction: Double      // 0…1
    let centerTop: String
    let centerBottom: String

    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.15), lineWidth: 26)
            Circle().trim(from: 0, to: max(0, min(1, keptFraction)))
                .stroke(Color.green, style: StrokeStyle(lineWidth: 26, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            Circle().trim(from: max(0, min(1, keptFraction)), to: 1)
                .stroke(Color.red, style: StrokeStyle(lineWidth: 26, lineCap: .butt))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text(centerTop).font(.system(size: 18, weight: .bold))
                Text(centerBottom).font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
        .frame(width: 170, height: 170)
    }
}

// Summary confirmation for deleting every group's non-keepers (no thumbnails).
struct PhotoDeleteAllConfirmSheet: View {
    @ObservedObject var engine: PhotoEngine
    let groups: [PhotoGroup]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private struct Totals { var before = 0; var freed = 0; var deleteCount = 0; var keepCount = 0; var groups = 0 }

    private var totals: Totals {
        var t = Totals()
        for g in groups {
            let live = g.photos.filter { !engine.deletedPaths.contains($0.fullPath) }
            guard live.contains(where: { $0.id != g.keeperID }) else { continue }
            t.groups += 1
            for p in live {
                t.before += p.sizeBytes
                if p.id == g.keeperID { t.keepCount += 1 }
                else { t.freed += p.sizeBytes; t.deleteCount += 1 }
            }
        }
        return t
    }

    var body: some View {
        let t = totals
        let after = t.before - t.freed
        let keptFraction = t.before > 0 ? Double(after) / Double(t.before) : 1

        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete all non-keepers").font(.headline)
                    Text("Across \(t.groups) similar group(s). Originals of the kept photos are not touched.")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(16)
            Divider()

            HStack(spacing: 28) {
                SpaceDonut(keptFraction: keptFraction,
                           centerTop: byteString(t.freed),
                           centerBottom: "freed")

                VStack(alignment: .leading, spacing: 12) {
                    legend(color: .green, label: "Kept", value: "\(t.keepCount) photo(s) · \(byteString(after))")
                    legend(color: .red, label: "Deleted", value: "\(t.deleteCount) photo(s) · \(byteString(t.freed))")
                    Divider().frame(width: 230)
                    statRow("Space before", byteString(t.before))
                    statRow("Space after", byteString(after))
                    statRow("Space freed", byteString(t.freed), highlight: .green)
                    statRow("Files deleted", "\(t.deleteCount) of \(t.deleteCount + t.keepCount)", highlight: .red)
                }
            }
            .padding(24)

            Spacer()
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(action: onConfirm) {
                    HStack(spacing: 6) { Image(systemName: "trash"); Text("Delete \(t.deleteCount) photo(s)") }
                        .fontWeight(.semibold).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.red).cornerRadius(7)
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction)
                .disabled(t.deleteCount == 0)
            }
            .padding(16)
        }
        .frame(width: 560, height: 430)
    }

    @ViewBuilder
    private func legend(color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 12, weight: .semibold))
                Text(value).font(.system(size: 10)).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func statRow(_ label: String, _ value: String, highlight: Color? = nil) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundColor(highlight ?? .primary)
        }
        .frame(width: 230)
    }

    private func byteString(_ bytes: Int) -> String {
        let kb = Double(bytes) / 1024, mb = kb / 1024, gb = mb / 1024
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.0f KB", kb)
    }
}
