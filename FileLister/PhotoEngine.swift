import Foundation
import AppKit
import ImageIO
import CoreGraphics
import Combine

// MARK: - Models

struct PhotoInfo: Identifiable, Hashable {
    let id = UUID()
    let path: String            // parent folder
    let name: String
    let sizeBytes: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let captureDate: Date?
    let cameraModel: String?
    let gps: (lat: Double, lon: Double)?
    let dHash: UInt64
    let pHash: UInt64

    var fullPath: String { (path as NSString).appendingPathComponent(name) }
    var pixels: Int { pixelWidth * pixelHeight }
    var isRaw: Bool {
        let raw: Set<String> = ["cr2", "cr3", "nef", "arw", "dng", "orf", "raf", "rw2"]
        return raw.contains((name as NSString).pathExtension.lowercased())
    }

    static func == (lhs: PhotoInfo, rhs: PhotoInfo) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct PhotoGroup: Identifiable {
    let id = UUID()
    var photos: [PhotoInfo]
    var keeperID: UUID

    var keeper: PhotoInfo? { photos.first { $0.id == keeperID } }
    // bytes freed if every non-keeper is removed
    var reclaimableBytes: Int {
        photos.filter { $0.id != keeperID }.reduce(0) { $0 + $1.sizeBytes }
    }
}

// MARK: - Engine

class PhotoEngine: ObservableObject {
    @Published var isScanning = false
    @Published var progress = 0.0
    @Published var status = "Ready to find similar photos"
    @Published var groups: [PhotoGroup] = []
    @Published var deletedPaths: Set<String> = []

    // Similarity threshold (0.70–1.00). 1.00 = identical; lower = more tolerant.
    @Published var matchThreshold: Double = 0.90
    // Optional: also require an EXIF signal (capture time / camera+dimensions) to group.
    @Published var requireExifCorroboration = false

    // Optional second pass: expand groups by shared metadata
    @Published var expandByMetadata = false
    @Published var expandUseTime = true
    @Published var expandUseGPS = false
    @Published var expandUseCamera = false

    @Published var lastLogURL: URL? = nil

    private var shouldStop = false
    private var cancellables = Set<AnyCancellable>()
    private var scannedRoots: [String] = []   // source roots, for replicating structure on export

    init() {
        // Re-pick keepers live when the best-copy priority changes in Settings
        PhotoPreferences.shared.$bestCopyPriority
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reapplyKeepers() }
            .store(in: &cancellables)
    }

    private let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp",
        "cr2", "cr3", "nef", "arw", "dng", "orf", "raf", "rw2"
    ]

    func stop() { shouldStop = true; status = "Stopping…" }

    func startScan(_ roots: [URL]) {
        guard !roots.isEmpty else { return }
        scannedRoots = roots.map { $0.path }
        shouldStop = false
        isScanning = true
        progress = 0
        groups = []
        deletedPaths = []
        status = "Scanning for images…"

        DispatchQueue.global(qos: .userInitiated).async {
            let urls = self.collectImageURLs(roots)
            guard !urls.isEmpty else {
                DispatchQueue.main.async { self.isScanning = false; self.status = "No images found." }
                return
            }

            // Build PhotoInfo (thumbnail + hashes + EXIF) for each image
            var photos: [PhotoInfo] = []
            photos.reserveCapacity(urls.count)
            for (i, url) in urls.enumerated() {
                if self.shouldStop { break }
                if let info = self.makePhotoInfo(url) { photos.append(info) }
                if i % 5 == 0 {
                    let p = Double(i) / Double(urls.count)
                    DispatchQueue.main.async { self.progress = p; self.status = "Analyzing \(i + 1)/\(urls.count): \(url.lastPathComponent)" }
                }
            }

            if self.shouldStop {
                DispatchQueue.main.async { self.isScanning = false; self.progress = 0; self.status = "Scan stopped." }
                return
            }

            let result = self.groupSimilar(photos)
            DispatchQueue.main.async {
                self.groups = result
                self.isScanning = false
                self.progress = 1.0
                let dupes = result.reduce(0) { $0 + $1.photos.count - 1 }
                self.status = "Found \(result.count) similar group(s) · \(dupes) removable photo(s)."
            }
        }
    }

    // MARK: Enumeration

    private func collectImageURLs(_ roots: [URL]) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for root in roots {
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                         options: [], errorHandler: { _, _ in true }) else { continue }
            while let u = en.nextObject() as? URL {
                if shouldStop { break }
                if imageExtensions.contains(u.pathExtension.lowercased()) { out.append(u) }
            }
        }
        return out
    }

    // MARK: Per-image analysis

    private func makePhotoInfo(_ url: URL) -> PhotoInfo? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]

        let pxW = (props[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let pxH = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0

        // EXIF dictionary
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let gpsDict = props[kCGImagePropertyGPSDictionary] as? [CFString: Any]

        var captureDate: Date?
        if let s = exif?[kCGImagePropertyExifDateTimeOriginal] as? String {
            captureDate = Self.exifDateFormatter.date(from: s)
        }
        let camera = tiff?[kCGImagePropertyTIFFModel] as? String

        var gps: (Double, Double)? = nil
        if let lat = gpsDict?[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gpsDict?[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = (gpsDict?[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -1.0 : 1.0
            let lonRef = (gpsDict?[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -1.0 : 1.0
            gps = (lat * latRef, lon * lonRef)
        }

        // One downsampled thumbnail (orientation-corrected), reused for both hashes
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else { return nil }
        let dh = Self.dHash(thumb)
        let ph = Self.pHash(thumb)

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        return PhotoInfo(path: url.deletingLastPathComponent().path,
                         name: url.lastPathComponent,
                         sizeBytes: size,
                         pixelWidth: pxW, pixelHeight: pxH,
                         captureDate: captureDate, cameraModel: camera, gps: gps,
                         dHash: dh, pHash: ph)
    }

    // MARK: Grouping (union-find over similarity)

    private func groupSimilar(_ photos: [PhotoInfo]) -> [PhotoGroup] {
        let n = photos.count
        guard n > 1 else { return [] }
        DispatchQueue.main.async { self.status = "Grouping similar photos…" }

        // similarity 0.90 → allow ~6 bits of pHash difference
        let maxHam = Int((1.0 - matchThreshold) * 64.0)

        var parent = Array(0..<n)
        func find(_ x: Int) -> Int { var r = x; while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }; return r }
        func union(_ a: Int, _ b: Int) { let ra = find(a), rb = find(b); if ra != rb { parent[ra] = rb } }

        for i in 0..<n {
            if shouldStop { break }
            for j in (i + 1)..<n {
                let dd = (photos[i].dHash ^ photos[j].dHash).nonzeroBitCount
                if dd > maxHam + 12 { continue }                 // cheap reject
                let pd = (photos[i].pHash ^ photos[j].pHash).nonzeroBitCount
                if pd <= maxHam {
                    if requireExifCorroboration && !exifCorroborates(photos[i], photos[j]) { continue }
                    union(i, j)
                }
            }
        }

        // Optional second pass: pull in additional photos that share selected metadata
        if expandByMetadata && (expandUseTime || expandUseGPS || expandUseCamera) {
            DispatchQueue.main.async { self.status = "Expanding groups by metadata…" }
            for i in 0..<n {
                if shouldStop { break }
                for j in (i + 1)..<n where find(i) != find(j) {
                    if metadataMatches(photos[i], photos[j]) { union(i, j) }
                }
            }
        }

        var buckets: [Int: [PhotoInfo]] = [:]
        for i in 0..<n { buckets[find(i), default: []].append(photos[i]) }

        return buckets.values
            .filter { $0.count > 1 }
            .map { members in
                let keeper = self.bestCopy(of: members)
                return PhotoGroup(photos: members, keeperID: keeper.id)
            }
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    // Two photos match on metadata if every ENABLED field matches (and at least one applied).
    private func metadataMatches(_ a: PhotoInfo, _ b: PhotoInfo) -> Bool {
        var applied = false
        if expandUseTime {
            guard let da = a.captureDate, let db = b.captureDate, abs(da.timeIntervalSince(db)) <= 2 else { return false }
            applied = true
        }
        if expandUseGPS {
            guard let ga = a.gps, let gb = b.gps, Self.metersBetween(ga, gb) <= 50 else { return false }
            applied = true
        }
        if expandUseCamera {
            guard let ca = a.cameraModel, let cb = b.cameraModel, ca == cb else { return false }
            applied = true
        }
        return applied
    }

    private static func metersBetween(_ a: (lat: Double, lon: Double), _ b: (lat: Double, lon: Double)) -> Double {
        let R = 6_371_000.0
        let dLat = (b.lat - a.lat) * .pi / 180, dLon = (b.lon - a.lon) * .pi / 180
        let la1 = a.lat * .pi / 180, la2 = b.lat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la1) * cos(la2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * R * asin(min(1, sqrt(h)))
    }

    func reapplyKeepers() {
        for i in groups.indices {
            groups[i].keeperID = bestCopy(of: groups[i].photos).id
        }
    }

    private func exifCorroborates(_ a: PhotoInfo, _ b: PhotoInfo) -> Bool {
        if let da = a.captureDate, let db = b.captureDate, abs(da.timeIntervalSince(db)) <= 2 { return true }
        if let ca = a.cameraModel, let cb = b.cameraModel, ca == cb,
           a.pixelWidth == b.pixelWidth, a.pixelHeight == b.pixelHeight { return true }
        return false
    }

    // Best copy per the user's configurable priority (Settings).
    func bestCopy(of photos: [PhotoInfo]) -> PhotoInfo {
        var best = photos[0]
        for p in photos.dropFirst() where PhotoPreferences.shared.isBetter(p, best) { best = p }
        return best
    }

    // Hamming-based similarity of a photo to its group keeper, as a percentage.
    func similarityToKeeper(_ photo: PhotoInfo, in group: PhotoGroup) -> Int {
        guard let keeper = group.keeper else { return 100 }
        let ham = (photo.pHash ^ keeper.pHash).nonzeroBitCount
        return Int(round((1.0 - Double(ham) / 64.0) * 100))
    }

    // MARK: Actions

    func setKeeper(_ photoID: UUID, in groupID: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == groupID }) else { return }
        groups[gi].keeperID = photoID
    }

    func recycle(_ photo: PhotoInfo) {
        let keeper = groups.first { $0.photos.contains(photo) }?.keeper
        let url = URL(fileURLWithPath: photo.fullPath)
        NSWorkspace.shared.recycle([url]) { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    self.deletedPaths.insert(photo.fullPath)
                    self.status = "Moved \(photo.name) to Trash."
                    self.writePhotoLog([(keeper, [photo])])
                } else {
                    self.status = "Couldn't delete \(photo.name)."
                }
            }
        }
    }

    func recycleNonKeepers(in group: PhotoGroup) {
        let targets = group.photos.filter { $0.id != group.keeperID && !deletedPaths.contains($0.fullPath) }
        guard !targets.isEmpty else { return }
        let keeper = group.keeper
        let urls = targets.map { URL(fileURLWithPath: $0.fullPath) }
        NSWorkspace.shared.recycle(urls) { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    for t in targets { self.deletedPaths.insert(t.fullPath) }
                    self.status = "Moved \(targets.count) photo(s) to Trash."
                    self.writePhotoLog([(keeper, targets)])
                } else {
                    self.status = "Some photos couldn't be deleted."
                }
            }
        }
    }

    // Global "delete all non-keepers" — one Trash op + one log across all groups.
    func recycleAllNonKeepers() {
        var batch: [(keeper: PhotoInfo?, deleted: [PhotoInfo])] = []
        var urls: [URL] = []
        for g in groups {
            let targets = g.photos.filter { $0.id != g.keeperID && !deletedPaths.contains($0.fullPath) }
            if !targets.isEmpty {
                batch.append((g.keeper, targets))
                urls.append(contentsOf: targets.map { URL(fileURLWithPath: $0.fullPath) })
            }
        }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.recycle(urls) { _, error in
            DispatchQueue.main.async {
                if error == nil {
                    for item in batch { for t in item.deleted { self.deletedPaths.insert(t.fullPath) } }
                    self.status = "Moved \(urls.count) photo(s) to Trash."
                    self.writePhotoLog(batch)
                } else {
                    self.status = "Some photos couldn't be deleted."
                }
            }
        }
    }

    // Copies every group's keeper into `destination`, replicating the folder
    // structure (relative to its scanned source root). Originals are untouched.
    func copyKeepers(to destination: URL) {
        let keepers = groups.compactMap { $0.keeper }
        guard !keepers.isEmpty else { return }
        isScanning = true
        status = "Copying keepers…"
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            var copied = 0, errors = 0
            var entries: [MergeLogEntry] = []
            for k in keepers {
                let rel = self.relativeDestination(for: k.fullPath)
                var dest = destination.appendingPathComponent(rel)
                try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                var suffix = 2
                while fm.fileExists(atPath: dest.path) {
                    let ext = dest.pathExtension
                    let base = ext.isEmpty ? dest.lastPathComponent : String(dest.lastPathComponent.dropLast(ext.count + 1))
                    let candidate = ext.isEmpty ? "\(base)_\(suffix)" : "\(base)_\(suffix).\(ext)"
                    dest = dest.deletingLastPathComponent().appendingPathComponent(candidate)
                    suffix += 1
                }
                let ok = (try? fm.copyItem(at: URL(fileURLWithPath: k.fullPath), to: dest)) != nil
                if ok { copied += 1 } else { errors += 1 }
                entries.append(MergeLogEntry(
                    action: ok ? "COPIED" : "ERROR", fileName: k.name, sourcePath: k.fullPath, sourceFolder: k.path,
                    destinationPath: ok ? dest.path : "", destinationFolder: ok ? dest.deletingLastPathComponent().path : "",
                    sizeBytes: k.sizeBytes, sha256: "pHash:" + String(k.pHash, radix: 16),
                    note: ok ? "keeper exported (\(k.pixelWidth)×\(k.pixelHeight))" : "copy failed"))
            }
            let cluster = MergeLogCluster(keepFolder: destination.path, otherFolders: [],
                                          resultName: destination.lastPathComponent, resultPath: destination.path,
                                          entries: entries)
            let report = MergeLogReport(timestamp: Date(), appVersion: MergeLogWriter.appVersion,
                                        mode: "Photo export (keepers copied, originals kept)", renameKeptFolder: false,
                                        clusters: [cluster])
            let logURL = MergeLogWriter.defaultAppLogDirectory().flatMap { MergeLogWriter.write(report, to: $0) }
            DispatchQueue.main.async {
                self.isScanning = false
                self.lastLogURL = logURL
                let errMsg = errors > 0 ? " (\(errors) failed)" : ""
                self.status = "Copied \(copied) keeper(s) to \"\(destination.lastPathComponent)\"\(errMsg). Originals untouched."
            }
        }
    }

    // Path of a file relative to its scanned root, prefixed by the root folder name.
    private func relativeDestination(for fullPath: String) -> String {
        let matches = scannedRoots.filter { fullPath == $0 || fullPath.hasPrefix($0 + "/") }
        if let root = matches.max(by: { $0.count < $1.count }) {
            let rootName = (root as NSString).lastPathComponent
            let after = String(fullPath.dropFirst(root.count))
            let rel = after.hasPrefix("/") ? String(after.dropFirst()) : after
            return (rootName as NSString).appendingPathComponent(rel)
        }
        return (fullPath as NSString).lastPathComponent
    }

    private func writePhotoLog(_ batch: [(keeper: PhotoInfo?, deleted: [PhotoInfo])]) {
        let clusters: [MergeLogCluster] = batch.compactMap { item in
            guard !item.deleted.isEmpty else { return nil }
            var entries: [MergeLogEntry] = []
            if let k = item.keeper {
                entries.append(MergeLogEntry(
                    action: "KEPT", fileName: k.name, sourcePath: k.fullPath, sourceFolder: k.path,
                    destinationPath: k.fullPath, destinationFolder: k.path, sizeBytes: k.sizeBytes,
                    sha256: "pHash:" + String(k.pHash, radix: 16),
                    note: "kept (best copy) · \(k.pixelWidth)×\(k.pixelHeight)"))
            }
            for d in item.deleted {
                entries.append(MergeLogEntry(
                    action: "TRASHED", fileName: d.name, sourcePath: d.fullPath, sourceFolder: d.path,
                    destinationPath: "Trash", destinationFolder: "Trash", sizeBytes: d.sizeBytes,
                    sha256: "pHash:" + String(d.pHash, radix: 16),
                    note: "similar photo · \(d.pixelWidth)×\(d.pixelHeight)"))
            }
            let keepPath = item.keeper?.fullPath ?? ""
            return MergeLogCluster(keepFolder: keepPath, otherFolders: [],
                                   resultName: item.keeper?.name ?? "—", resultPath: keepPath, entries: entries)
        }
        guard !clusters.isEmpty, let dir = MergeLogWriter.defaultAppLogDirectory() else { return }
        let report = MergeLogReport(timestamp: Date(), appVersion: MergeLogWriter.appVersion,
                                    mode: "Photo cleanup (similar photos)", renameKeptFolder: false, clusters: clusters)
        lastLogURL = MergeLogWriter.write(report, to: dir)
    }

    // MARK: Hashing

    private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // Draw a CGImage into a w×h 8-bit grayscale buffer.
    private static func grayMatrix(_ cg: CGImage, _ w: Int, _ h: Int) -> [Double]? {
        var data = [UInt8](repeating: 0, count: w * h)
        let cs = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data.map { Double($0) }
    }

    // dHash: 9×8 grayscale, compare adjacent pixels left→right → 64 bits.
    static func dHash(_ cg: CGImage) -> UInt64 {
        guard let g = grayMatrix(cg, 9, 8) else { return 0 }
        var hash: UInt64 = 0, bit = 0
        for row in 0..<8 {
            for col in 0..<8 {
                if g[row * 9 + col] < g[row * 9 + col + 1] { hash |= (UInt64(1) << UInt64(bit)) }
                bit += 1
            }
        }
        return hash
    }

    // pHash: 32×32 grayscale → 2D DCT → top-left 8×8 low frequencies → bit = coeff > median.
    private static let dctCos: [[Double]] = {
        let N = 32
        var t = [[Double]](repeating: [Double](repeating: 0, count: N), count: 8)
        for k in 0..<8 { for x in 0..<N { t[k][x] = cos(Double.pi / Double(N) * (Double(x) + 0.5) * Double(k)) } }
        return t
    }()

    static func pHash(_ cg: CGImage) -> UInt64 {
        let N = 32
        guard let g = grayMatrix(cg, N, N) else { return 0 }
        // Separable DCT: rows first (8×N), then columns (8×8).
        var tmp = [[Double]](repeating: [Double](repeating: 0, count: N), count: 8)
        for u in 0..<8 {
            for y in 0..<N {
                var s = 0.0
                for x in 0..<N { s += g[x * N + y] * dctCos[u][x] }
                tmp[u][y] = s
            }
        }
        var freqs = [Double](repeating: 0, count: 64)
        for u in 0..<8 {
            for v in 0..<8 {
                var s = 0.0
                for y in 0..<N { s += tmp[u][y] * dctCos[v][y] }
                freqs[u * 8 + v] = s
            }
        }
        // median of AC coefficients (exclude DC at index 0)
        let ac = Array(freqs[1...]).sorted()
        let median = ac[ac.count / 2]
        var hash: UInt64 = 0
        for i in 0..<64 { if freqs[i] > median { hash |= (UInt64(1) << UInt64(i)) } }
        return hash
    }
}
